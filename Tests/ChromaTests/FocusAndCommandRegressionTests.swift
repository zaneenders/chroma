import Testing

@testable import Chroma

@MainActor
struct FocusAndCommandRegressionTests {
  @MainActor private final class Harness {
    let context = RenderContext()
    let producer = FrameProducer()

    func render(_ content: any Block, input: InputState = InputState()) {
      _ = producer.render(
        content: content, viewport: Size(width: 200, height: 100),
        input: input, context: context, onChange: {})
    }
  }

  @Test func commandHandlerDoesNotInterceptSibling() {
    let harness = Harness()
    let target = FocusTarget()
    var calls: [String] = []
    let content = VStack {
      Button("A") {}.onCommand(.application("test")) {
        calls.append("A")
        return .handled
      }
      Button("B") {}.focusTarget(target).onCommand(.application("test")) {
        calls.append("B")
        return .handled
      }
    }
    target.focus()
    harness.render(content)
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == ["B"])
  }

  @Test func prunedCommandScopeDoesNotInterceptSibling() {
    let harness = Harness()
    var calls = 0
    let content = VStack {
      EmptyBlock().onCommand(.application("test")) {
        calls += 1
        return .handled
      }
      Button("B") {}
    }
    harness.render(content)
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == 0)
  }

  @Test func focusRecoversAfterEmptyTree() {
    let harness = Harness()
    var calls = 0
    let replacement = Button("After") { calls += 1 }
    harness.render(Button("Before") {})
    harness.render(EmptyBlock())
    #expect(harness.context.interaction.selection == nil)
    harness.render(replacement)
    harness.render(replacement, input: InputState(commands: [.action(.activate)]))
    #expect(calls == 1)
  }

  @Test func focusRecoversWhenReplacementPathEndsAtGroup() {
    let harness = Harness()
    var calls = 0
    harness.render(Button("Before") {})
    let replacement = VStack { Button("After") { calls += 1 } }
    harness.render(replacement)
    harness.render(replacement, input: InputState(commands: [.action(.activate)]))
    #expect(calls == 1)
  }
}
