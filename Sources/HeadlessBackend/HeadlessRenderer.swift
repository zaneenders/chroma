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
public final class HeadlessRenderer: Renderer {
  public let name = "Headless"

  public var content: (any Block)? {
    didSet { frameProducer.reset() }
  }
  private let frameProducer = FrameProducer()

  public var onRedrawRequested: (@MainActor () -> Void)?
  public var frameObserver: FrameObserver?
  public var onClose: (() -> Void)?
  public var viewport: Size

  public private(set) var title: String?
  public private(set) var lastFrame: HeadlessFrame?

  package let interaction = Interaction()

  public init(size: Size = Size(width: 800, height: 600)) {
    self.viewport = size
  }

  public func run(title: String) {
    self.title = title
    _ = render()
  }

  @discardableResult
  public func render(input: InputState = InputState()) -> HeadlessFrame {
    let drawList = frameProducer.render(
      content: content, viewport: viewport, input: input, context: context,
      onChange: { [weak self] in self?.onRedrawRequested?() })
    _ = interaction.consumeRedrawRequest()
    frameObserver?(FrameObservation(drawList: drawList, viewport: viewport))

    let frame = HeadlessFrame(viewport: viewport, commands: drawList.commands)
    lastFrame = frame
    return frame
  }

  public func close() {
    frameProducer.reset()
    onClose?()
  }
}
