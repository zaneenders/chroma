import Chroma

public struct HeadlessFrame: Equatable, Sendable {
  public let viewport: Size
  public let commands: [DrawCommand]

  public init(viewport: Size, commands: [DrawCommand]) {
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
  public var nextAnimationDeadline: Double? { runtime.nextAnimationDeadline }
  public var needsAnimationFrame: Bool { runtime.needsAnimationFrame }
  public var onRedrawRequested: (@MainActor () -> Void)?
  public var onClose: (() -> Void)?
  public var viewport: Size

  public private(set) var title: String?
  public private(set) var lastFrame: HeadlessFrame?

  package let runtime = WindowRuntime()

  public init(size: Size = Size(width: 800, height: 600)) {
    self.viewport = size
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
    let drawList = runtime.render(
      viewport: viewport, input: input,
      onChange: { [weak self] in self?.onRedrawRequested?() })
    runtime.scheduler.recordProducedFrame()
    _ = interaction.consumeRedrawRequest()
    runtime.observe(drawList, viewport: viewport)

    let frame = HeadlessFrame(viewport: viewport, commands: drawList.commands)
    lastFrame = frame
    return frame
  }

  /// Explicitly step animation paint without evaluating the content tree.
  @discardableResult
  public func renderAnimations() -> HeadlessFrame {
    let list = runtime.renderAnimations()
    runtime.scheduler.recordProducedFrame()
    runtime.observe(list, viewport: viewport)
    let frame = HeadlessFrame(viewport: viewport, commands: list.commands)
    lastFrame = frame
    return frame
  }

  public func resolve(_ input: KeyboardInput) -> ResolvedKeyboardInput? {
    runtime.resolve(input)
  }

  public var keyBindings: KeyBindings {
    get { runtime.keyBindings }
    set { runtime.keyBindings = newValue }
  }

  public func close() {
    runtime.reset()
    onClose?()
  }
}
