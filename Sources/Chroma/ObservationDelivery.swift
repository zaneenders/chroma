// Capture the scheduler when subscribing: observation callbacks can arrive on any executor.
// Tests can control delivery without relying on executor ordering or elapsed time.
enum ObservationDelivery {
  @TaskLocal static var enqueue: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = {
    action in
    Task { @MainActor in action() }
  }
}
