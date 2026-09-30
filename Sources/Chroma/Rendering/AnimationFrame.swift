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

  public func animationFrame(active: Bool = true, updatesPerSecond: Double = 60) -> AnimationFrame {
    precondition(updatesPerSecond.isFinite && updatesPerSecond > 0 && updatesPerSecond <= 240)
    if active {
      let now = interaction.animationFrame.timestamp
      requestAnimation(at: (floor(now * updatesPerSecond) + 1) / updatesPerSecond)
    }
    return interaction.animationFrame
  }
}
