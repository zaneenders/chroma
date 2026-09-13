public struct AnimationFrame: Equatable, Sendable {
  public let timestamp: Double

  public init(timestamp: Double) {
    self.timestamp = timestamp
  }
}

extension RenderContext {
  public func animationFrame(active: Bool = true) -> AnimationFrame {
    if active { interaction.animationRequested = true }
    return interaction.animationFrame
  }
}
