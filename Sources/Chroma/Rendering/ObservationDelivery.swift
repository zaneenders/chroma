enum ObservationDelivery {
  @TaskLocal static var enqueue: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = {
    action in
    Task(priority: .userInitiated) { @MainActor in action() }
  }
}
