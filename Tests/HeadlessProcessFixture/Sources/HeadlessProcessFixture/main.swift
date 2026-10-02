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
    if ProcessInfo.processInfo.environment["CHROMA_FIXTURE_FLOOD_STDERR"] == "1" {
      // More than a pipe buffer: startup can only complete if the driver drains
      // stderr concurrently with waiting for the first stdout response.
      try? FileHandle.standardError.write(
        contentsOf: Data((String(repeating: "diagnostic ", count: 32_768) + "\n").utf8))
    }
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
