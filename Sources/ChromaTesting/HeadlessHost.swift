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

  public var content: (any Block)? {
    get { runtime.content }
    set {
      runtime.content = newValue
    }
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

  @discardableResult
  public func render(input: InputState = InputState()) -> HeadlessFrame {
    runtime.scheduler.recordProducedFrame()
    runtime.scheduler.consumeContentRequest()
    let drawList = runtime.render(
      viewport: viewport, input: input,
      onChange: { [weak self] in self?.requestRedraw() })
    _ = interaction.consumeRedrawRequest()
    runtime.observe(drawList, viewport: viewport)

    let frame = HeadlessFrame(viewport: viewport, commands: drawList.commands)
    lastFrame = frame
    return frame
  }

  /// Applies one input event through the runtime without presenting a frame.
  /// Events before the first frame are queued in their original order.
  public func sendInput(_ input: InputState) {
    runtime.handleInput(input)
  }

  /// Presents pending work immediately, ignoring the native frame deadline.
  /// Returns nil when idle, making coalesced input and scheduling testable without
  /// a native event loop or artificial sleeps.
  @discardableResult
  public func renderIfNeeded() -> HeadlessFrame? {
    guard let scheduled = runtime.scheduler.nextFrame else { return nil }
    runtime.scheduler.recordProducedFrame()
    let drawList = runtime.renderScheduled(
      scheduled.kind, viewport: viewport,
      onChange: { [weak self] in self?.requestRedraw() })
    _ = interaction.consumeRedrawRequest()
    runtime.observe(drawList, viewport: viewport)
    let frame = HeadlessFrame(viewport: viewport, commands: drawList.commands)
    lastFrame = frame
    return frame
  }

  /// Presents changes using the same refresh-rate scheduler as native hosts.
  public func startPresenting(onlyChanges: Bool = true, _ present: @escaping @MainActor (HeadlessFrame) -> Void) {
    runtime.scheduler.onFrame = { [weak self] kind in
      guard let self else { return }
      let drawList = runtime.renderScheduled(
        kind, viewport: viewport,
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
