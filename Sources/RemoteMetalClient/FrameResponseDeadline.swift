import Foundation

enum FrameResponseDeadline {
  static let timeout: TimeInterval = 10

  static func hasExpired(
    since started: TimeInterval, now: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) -> Bool {
    now - started >= timeout
  }
}
