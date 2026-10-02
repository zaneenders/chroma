import Chroma
import ChromaHeadless
import Foundation
import Observation

/// A real subprocess fixture: stdout must contain JSON even when app code logs.
@main
struct HeadlessProcessFixture: HeadlessApp {
  @Observable @MainActor final class Model {
    var phase = "idle"
    deinit { print("fixture: model deinit print") }
  }

  private let model: Model

  init() {
    print("fixture: initializer print")
    model = Model()
  }

  var frameObserver: FrameObserver? {
    { _ in print("fixture: frame observer print") }
  }

  var body: some Block {
    VStack(spacing: 12) {
      Text(model.phase)
      Button("Start async") {
        print("fixture: button callback print")
        model.phase = "waiting"
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(50))
          model.phase = "complete"
          print("fixture: async print")
          // An unbuffered marker lets the driver wait for actual completion
          // while keeping stdin idle, instead of guessing a sufficient delay.
          try? FileHandle.standardError.write(contentsOf: Data("fixture: async complete\n".utf8))
        }
      }
    }.padding(16)
  }
}
