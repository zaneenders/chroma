import AppKit
import Chroma
import MetalKit

public protocol MetalApp: App {}

extension MetalApp {
  @MainActor
  public static func main() throws {
    let app = Self()
    try app.run(on: MetalRenderer(size: app.windowSize))
  }
}

@MainActor
public final class MetalRenderer: NSObject, Renderer, MTKViewDelegate, NSWindowDelegate {
  public let name = "Metal"
  public var content: (any Block)? {
    didSet {
      producer.reset()
      view.needsDisplay = true
    }
  }
  public var frameObserver: FrameObserver?
  public var onClose: (() -> Void)?
  package let interaction = Interaction()
  private let producer = FrameProducer()
  private let view: ChromaInputView
  private let queue: MTLCommandQueue
  private let displayRenderer: MetalDisplayListRenderer
  private var window: NSWindow?
  private var keyBindings = KeyBindings()
  private var minimumRefreshRate: Double = 0
  private var lastFrameTime: Double = 0

  public init(size: Size = Size(width: 800, height: 600)) throws {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw BackendError.unavailable(backend: "Metal", reason: "no compatible GPU or command queue was found")
    }
    self.queue = queue
    let view = ChromaInputView(
      frame: CGRect(x: 0, y: 0, width: CGFloat(size.width), height: CGFloat(size.height)), device: device)
    view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1)
    view.isPaused = true
    view.enableSetNeedsDisplay = true
    self.view = view
    displayRenderer = try MetalDisplayListRenderer(device: device, pixelFormat: view.colorPixelFormat)
    super.init()
    view.delegate = self
    // Process each input event before the next one (including clipboard operations).
    view.onInputAvailable = { [weak self] in self?.view.draw() }
    view.onKey = { [weak self] input in self?.handleKey(input) }
    interaction.onRedrawRequested = { [weak self] in self?.view.needsDisplay = true }
  }

  package func setKeyBindings(_ bindings: KeyBindings) { keyBindings = bindings }

  package func setMinimumRefreshRate(_ refreshRate: Double) {
    minimumRefreshRate = refreshRate.isFinite ? min(240, max(0, refreshRate)) : 0
    updateFrameScheduling()
  }

  private func updateFrameScheduling() {
    let rate = max(minimumRefreshRate, producer.needsAnimationFrame ? 60 : 0)
    view.preferredFramesPerSecond = max(1, Int(rate))
    view.isPaused = rate == 0
  }

  @diagnose(UnnecessaryUnsafe, as: warning, reason: "SDK compatibility")
  public func run(title: String) throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let window = NSWindow(
      contentRect: view.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    self.window = window
    window.isReleasedWhenClosed = false
    window.title = title
    window.contentView = view
    window.delegate = self
    window.collectionBehavior.insert(.fullScreenPrimary)
    window.center()
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(view)
    view.needsDisplay = true
    app.activate()
    app.run()
    producer.reset()
    self.window = nil
  }

  public func windowWillClose(_ notification: Notification) {
    view.isPaused = true
    producer.reset()
    onClose?()
    NSApplication.shared.stop(nil)
    // Wake the run loop so run() returns even when the window was its last event source.
    if let event = NSEvent.otherEvent(
      with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)
    {
      NSApplication.shared.postEvent(event, atStart: false)
    }
  }

  private var pendingCommands: [Command] = []
  private var pendingTextEvents: [TextEditEvent] = []

  func handleKey(_ input: KeyboardInput) {
    guard let resolved = interaction.resolve(input, appBindings: keyBindings) else { return }
    switch resolved {
    case .command(let command): pendingCommands.append(command)
    case .text(let event): applyTextEvent(event)
    }
    view.draw()
  }

  private func applyTextEvent(_ event: TextEditEvent) {
    switch event {
    case .copy:
      if let text = interaction.copyText() { _ = copy(text) }
    case .cut:
      if let text = interaction.editableSelectionText(), !text.isEmpty, copy(text) {
        pendingTextEvents.append(.deleteForward)
      }
    case .paste:
      if interaction.isTextEditing, let text = NSPasteboard.general.string(forType: .string) {
        pendingTextEvents.append(.insert(text))
      }
    case .selectAll where !interaction.isTextEditing:
      interaction.selectAll(at: interaction.input.pointerPosition)
    default: pendingTextEvents.append(event)
    }
  }

  private func copy(_ text: String) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
  }

  public func draw(in view: MTKView) {
    let viewport = Size(width: Float(view.bounds.width), height: Float(view.bounds.height))
    guard viewport.width > 0, viewport.height > 0 else { return }
    var input = self.view.frameInput()
    input.commands = pendingCommands
    input.textEvents = pendingTextEvents
    pendingCommands.removeAll(keepingCapacity: true)
    pendingTextEvents.removeAll(keepingCapacity: true)
    let now = ProcessInfo.processInfo.systemUptime
    if lastFrameTime > 0, now > lastFrameTime { interaction.frameRate = 1 / (now - lastFrameTime) }
    lastFrameTime = now
    let list = producer.render(
      content: content, viewport: viewport, input: input, context: context,
      onChange: { [weak self] in self?.view.needsDisplay = true })
    updateFrameScheduling()
    let redraw = interaction.consumeRedrawRequest()
    defer { if redraw { view.needsDisplay = true } }
    guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor else {
      view.needsDisplay = true
      return
    }
    let scale = Point(
      x: Float(drawable.texture.width) / viewport.width,
      y: Float(drawable.texture.height) / viewport.height)
    frameObserver?(FrameObservation(drawList: list, viewport: viewport, rasterScale: scale))
    do {
      guard
        let frame = try displayRenderer.prepareFrame(
          list.culled(to: viewport), viewport: viewport, rasterScale: scale, queue: queue, renderPass: pass)
      else {
        view.needsDisplay = true
        return
      }
      _ = frame.submit(presenting: drawable)
    } catch {
      NSLog("Chroma Metal rendering failed: %@", String(describing: error))
    }
  }

  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    view.needsDisplay = true
  }
}
