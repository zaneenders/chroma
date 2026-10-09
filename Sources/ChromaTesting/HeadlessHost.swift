import Chroma

public struct HeadlessFrame: Equatable, Sendable {
  public let viewport: Size
  public let commands: [DrawEntry]

  public init(viewport: Size, commands: [DrawEntry]) {
    self.viewport = viewport
    self.commands = commands
  }
}

@MainActor
public final class HeadlessHost: Host {
  public let name = "Headless"

  public var build: LayoutBuilder? {
    get { runtime.build }
    set { runtime.build = newValue }
  }
  public var frameObserver: FrameObserver? {
    get { runtime.frameObserver }
    set { runtime.frameObserver = newValue }
  }
  public var onRedrawRequested: (@MainActor () -> Void)?
  public var onClose: (() -> Void)?
  public var viewport: Size

  public private(set) var title: String?
  public private(set) var lastFrame: HeadlessFrame?

  package let runtime = WindowRuntime()

  public init(size: Size = Size(width: 800, height: 600)) {
    self.viewport = size
    interaction.onRedrawRequested = { [weak self] in self?.requestRedraw() }
  }

  public func launch<A: App>(_ app: A) throws {
    try app.run(on: self)
  }

  public func run(title: String) {
    self.title = title
    _ = render()
  }

  /// A snapshot unless an explicit input event is supplied. Rendering never replays prior edges.
  @discardableResult
  public func render(input: InputState? = nil) -> HeadlessFrame {
    runtime.scheduler.recordProducedFrame()
    let drawList = runtime.render(
      viewport: viewport, input: input ?? interaction.input.settled, processingInput: input != nil,
      onChange: { [weak self] in self?.requestRedraw() })
    _ = interaction.consumeRedrawRequest()
    runtime.observe(drawList, viewport: viewport)

    let frame = HeadlessFrame(viewport: viewport, commands: drawList.commands)
    lastFrame = frame
    return frame
  }

  /// Applies one input event through the runtime without presenting a frame.
  /// Events before the first frame or sent by another event callback keep their original order.
  public func sendInput(_ input: InputState) {
    runtime.handleInput(input)
  }

  /// Resolves and delivers a raw key against one fresh registration, preserving FIFO order.
  public func sendKeyboardInput(_ input: KeyboardInput, state: InputState = InputState()) {
    runtime.handleKeyboardInput(input) { [weak self] resolved in
      var state = state
      switch resolved {
      case .command(let command): state.commands = [command]
      case .text(let event): state.textEvents = [event]
      }
      self?.runtime.handleInput(state)
    }
  }

  /// Presents pending work immediately, ignoring the native frame deadline.
  /// Returns nil when idle, making coalesced input and scheduling testable without
  /// a native event loop or artificial sleeps.
  @discardableResult
  public func renderIfNeeded() -> HeadlessFrame? {
    guard case .some = runtime.scheduler.nextFrame else { return nil }
    runtime.scheduler.recordProducedFrame()
    let drawList = runtime.renderScheduled(
      viewport: viewport,
      onChange: { [weak self] in self?.requestRedraw() })
    _ = interaction.consumeRedrawRequest()
    runtime.observe(drawList, viewport: viewport)
    let frame = HeadlessFrame(viewport: viewport, commands: drawList.commands)
    lastFrame = frame
    return frame
  }

  /// Presents changes using the same refresh-rate scheduler as native hosts.
  public func startPresenting(onlyChanges: Bool = true, _ present: @escaping @MainActor (HeadlessFrame) -> Void) {
    runtime.scheduler.onFrame = { [weak self] in
      guard let self else { return }
      let drawList = runtime.renderScheduled(
        viewport: viewport,
        onChange: { [weak self] in self?.requestRedraw() })
      _ = interaction.consumeRedrawRequest()
      runtime.observe(drawList, viewport: viewport)
      let frame = HeadlessFrame(viewport: viewport, commands: drawList.commands)
      lastFrame = frame
      present(frame)
      if !onlyChanges { runtime.scheduler.requestContent() }
    }
    if !onlyChanges { runtime.scheduler.requestContent() }
    runtime.scheduler.isReady = true
  }

  private func requestRedraw() {
    runtime.scheduler.requestContent()
    onRedrawRequested?()
  }

  public func resolve(_ input: KeyboardInput) -> ResolvedKeyboardInput? {
    runtime.resolve(input)
  }

  public var keyBindings: KeyBindings {
    get { runtime.keyBindings }
    set { runtime.keyBindings = newValue }
  }

  public func close() {
    runtime.scheduler.isReady = false
    runtime.scheduler.onFrame = nil
    runtime.reset()
    onClose?()
  }
}
