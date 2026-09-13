import Observation

@Observable
@MainActor
final class CaretClock {
  private(set) var visible = true
  @ObservationIgnored private var task: Task<Void, Never>?

  func setActive(_ active: Bool) {
    guard active else {
      task?.cancel()
      task = nil
      visible = true
      return
    }
    guard task == nil else { return }
    task = Task { [weak self] in
      while !Task.isCancelled {
        let seconds = self?.visible == true ? 0.72 : 0.48
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
        guard let self else { return }
        self.visible.toggle()
      }
    }
  }

  deinit { task?.cancel() }
}
