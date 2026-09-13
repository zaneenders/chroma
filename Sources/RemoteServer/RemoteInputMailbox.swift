import Dispatch
import RemoteProtocol
import Synchronization

final class RemoteInputMailbox: Sendable {
  static let maximumMessages = 256
  static let maximumBytes = 8 * 1024 * 1024
  static let batchSize = 32

  private struct State: Sendable {
    var pending: [(RemoteMessage, Int)] = []
    var bytes = 0
    var scheduled = false
    var closed = false
  }
  private let state = Mutex(State())
  private let deliver: @MainActor @Sendable (RemoteMessage) -> Void

  init(deliver: @escaping @MainActor @Sendable (RemoteMessage) -> Void) {
    self.deliver = deliver
  }

  func enqueue(_ message: RemoteMessage, byteCount: Int) -> Bool {
    let result = state.withLock { state -> (accepted: Bool, schedule: Bool) in
      guard !state.closed, state.pending.count < Self.maximumMessages,
        byteCount >= 0, byteCount <= Self.maximumBytes - state.bytes
      else {
        state.closed = true
        state.pending.removeAll()
        state.bytes = 0
        return (false, false)
      }
      state.pending.append((message, byteCount))
      state.bytes += byteCount
      let shouldSchedule = !state.scheduled
      state.scheduled = true
      return (true, shouldSchedule)
    }
    if result.schedule { scheduleDrain() }
    return result.accepted
  }

  func close() {
    state.withLock { state in
      state.closed = true
      state.pending.removeAll()
      state.bytes = 0
    }
  }

  private func scheduleDrain() {
    DispatchQueue.main.async { [self] in drain() }
  }

  @MainActor private func drain() {
    for _ in 0..<Self.batchSize {
      let message = state.withLock { state -> RemoteMessage? in
        guard !state.closed, !state.pending.isEmpty else {
          state.scheduled = false
          return nil
        }
        let (message, cost) = state.pending.removeFirst()
        state.bytes -= cost
        return message
      }
      guard let message else { return }
      deliver(message)
    }
    scheduleDrain()
  }
}
