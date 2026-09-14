import Synchronization
import Testing

@testable import Chroma

private final class PendingObservationChanges: Sendable {
  let actions = Mutex<[@MainActor @Sendable () -> Void]>([])

  func enqueue(_ action: @escaping @MainActor @Sendable () -> Void) {
    actions.withLock { $0.append(action) }
  }

  @MainActor func drain() {
    while true {
      let batch = actions.withLock { actions in
        defer { actions.removeAll() }
        return actions
      }
      guard !batch.isEmpty else { return }
      for action in batch { action() }
    }
  }
}

private enum ObservationTestScope {
  @TaskLocal static var pending: PendingObservationChanges?
}

// Each test gets its own scheduler, including when tests run concurrently.
struct ControlledObservationDelivery: SuiteTrait, TestTrait, TestScoping {
  var isRecursive: Bool { true }

  func provideScope(
    for test: Test, testCase: Test.Case?,
    performing function: @Sendable () async throws -> Void
  ) async throws {
    let pending = PendingObservationChanges()
    try await ObservationTestScope.$pending.withValue(pending) {
      try await ObservationDelivery.$enqueue.withValue({ pending.enqueue($0) }) {
        try await function()
      }
    }
  }
}

@MainActor func drainObservationChanges() async {
  guard let pending = ObservationTestScope.pending else {
    Issue.record("Observation delivery must be controlled by the test scope")
    return
  }
  pending.drain()
}
