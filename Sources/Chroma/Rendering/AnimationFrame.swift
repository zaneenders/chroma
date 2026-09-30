import Foundation

public struct AnimationFrame: Equatable, Sendable {
  public let timestamp: Double

  public init(timestamp: Double) {
    self.timestamp = timestamp
  }
}

extension BlockContext {
  public var animationTimestamp: Double { interaction.animationFrame.timestamp }

  public func requestAnimation(at deadline: Double) {
    precondition(deadline.isFinite && deadline > animationTimestamp)
    interaction.nextAnimationDeadline = min(interaction.nextAnimationDeadline ?? deadline, deadline)
  }

  /// Schedule a future frame at the next tick of an explicit animation rate.
  /// Read `animationTimestamp` separately; reading time does not request a frame.
  public func requestAnimation(updatesPerSecond: Double) {
    precondition(updatesPerSecond.isFinite && updatesPerSecond > 0 && updatesPerSecond <= 240)
    let now = animationTimestamp
    requestAnimation(at: (floor(now * updatesPerSecond) + 1) / updatesPerSecond)
  }
}
