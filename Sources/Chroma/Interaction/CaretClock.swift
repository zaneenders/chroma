import Observation

@Observable
@MainActor
final class CaretClock {
  private(set) var visible = true
  @ObservationIgnored private(set) var task: Task<Void, Never>?
  @ObservationIgnored private let sleep: @MainActor @Sendable (Duration) async throws -> Void

  init(
    sleep: @escaping @MainActor @Sendable (Duration) async throws -> Void = {
      try await Task.sleep(for: $0)
    }
  ) {
    self.sleep = sleep
  }

  func setActive(_ active: Bool) {
    guard active else {
      task?.cancel()
      task = nil
      visible = true
      return
    }
    guard task == nil else { return }
    let sleep = sleep
    task = Task { [weak self] in
      while !Task.isCancelled {
        let seconds = self?.visible == true ? 0.72 : 0.48
        do { try await sleep(.seconds(seconds)) } catch { return }
        // Cancellation may arrive after the sleep finishes but before this task resumes.
        guard !Task.isCancelled, let self else { return }
        self.visible.toggle()
      }
    }
  }

  deinit { task?.cancel() }
}
