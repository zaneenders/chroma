public struct FrameObservation: Sendable {
  public let drawList: DrawList
  public let viewport: Size
  public let rasterScale: Point?

  public init(drawList: DrawList, viewport: Size, rasterScale: Point? = nil) {
    self.drawList = drawList
    self.viewport = viewport
    self.rasterScale = rasterScale
  }
}

public typealias FrameObserver = @MainActor (FrameObservation) -> Void
