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

  func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let phase = buffer.text(Text(model.phase), context: context.childScope(0))
    let tick = buffer.text(Text("Tick: \(model.tick)"), context: context.childScope(1))
    let startAsync = buffer.button(
      Button("Start async") {
        model.phase = "waiting"
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(50))
          model.phase = "complete"
        }
      }, context: context.childScope(2))
    let startTimer = buffer.button(
      Button("Start timer") {
        Task { @MainActor in
          for tick in 1...3 {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            model.tick = tick
          }
        }
      }, context: context.childScope(3))
    let stack = buffer.stack([phase, tick, startAsync, startTimer], axis: .vertical, spacing: 12, context: context)
    return buffer.padding(stack, 16, context: context)
  }
}
