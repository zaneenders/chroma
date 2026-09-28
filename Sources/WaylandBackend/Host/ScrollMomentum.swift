import Foundation

struct ScrollMomentum {
  private static let releaseSpeedMultiplier: Float = 1.25
  private static let decayRate: Double = 6

  private var lastEventTime: UInt32?
  private var velocity: Float = 0
  private var lastFrameTime: TimeInterval?

  var isActive: Bool { lastFrameTime != nil }

  mutating func cancel() {
    lastEventTime = nil
    velocity = 0
    lastFrameTime = nil
  }

  mutating func record(delta: Float, time: UInt32) {
    lastFrameTime = nil
    if let previous = lastEventTime {
      let elapsed = time &- previous
      if elapsed > 0 && elapsed <= 100 {
        velocity = max(-4000, min(4000, delta * 1000 / Float(elapsed) * Self.releaseSpeedMultiplier))
      } else if elapsed > 100 {
        velocity = 0
      }
    } else {
      velocity = 0
    }
    lastEventTime = time
  }

  mutating func stop(time: UInt32, now: TimeInterval) {
    guard let previous = lastEventTime, time &- previous <= 100,
      abs(velocity) >= 30
    else {
      cancel()
      return
    }
    lastEventTime = nil
    lastFrameTime = now
  }

  mutating func advance(now: TimeInterval) -> Float {
    guard let previous = lastFrameTime else { return 0 }
    let elapsed = now - previous
    guard elapsed >= 0 && elapsed <= 0.25 else {
      cancel()
      return 0
    }
    let decay = Float(exp(-Self.decayRate * elapsed))
    let delta = velocity * (1 - decay) / Float(Self.decayRate)
    velocity *= decay
    lastFrameTime = now
    if abs(velocity) < 5 { cancel() }
    return delta
  }
}
