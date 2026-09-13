/// Timing shared by every animated control evaluated in a produced frame.
public struct AnimationFrame: Equatable, Sendable {
  /// Monotonic seconds since system startup, not wall-clock time.
  public let timestamp: Double

  public init(timestamp: Double) {
    self.timestamp = timestamp
  }
}

extension RenderContext {
  /// Read the current frame's timestamp and request continued rendering while active.
  /// Call during drawing. Demand is rebuilt each frame, so removing or pausing a
  /// control stops its contribution. The backend owns cadence and backpressure;
  /// this method never starts a timer or advances time by a fixed frame increment.
  public func animationFrame(active: Bool = true) -> AnimationFrame {
    if active { interaction.animationRequested = true }
    return interaction.animationFrame
  }
}
