@MainActor
final class CaretClock {
  private var startedAt: Double?

  func isVisible(at timestamp: Double) -> Bool {
    guard let startedAt else { return true }
    return max(0, timestamp - startedAt).truncatingRemainder(dividingBy: 1.2) < 0.72
  }

  func setActive(_ active: Bool, timestamp: Double = 0) {
    if active {
      if startedAt == nil { startedAt = timestamp }
    } else {
      startedAt = nil
    }
  }
}
