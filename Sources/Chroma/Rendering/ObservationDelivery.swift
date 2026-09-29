enum ObservationDelivery {
  @TaskLocal static var enqueue: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = {
    action in
    Task { @MainActor in action() }
  }
}
