import Chroma
import ChromaHeadless
import Observation

/// A real subprocess fixture rendered through the framework’s stdout backend.
@main
struct HeadlessProcessFixture: HeadlessApp {
  @Observable @MainActor final class Model {
    var phase = "idle"
    var tick = 0
  }

  private let model: Model

  init() {
    model = Model()
  }

  var body: some Block {
    VStack(spacing: 12) {
      Text(model.phase)
      Text("Tick: \(model.tick)")
      Button("Start async") {
        model.phase = "waiting"
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(50))
          model.phase = "complete"
        }
      }
      Button("Start timer") {
        Task { @MainActor in
          for tick in 1...3 {
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
            model.tick = tick
          }
        }
      }
    }.padding(16)
  }
}
