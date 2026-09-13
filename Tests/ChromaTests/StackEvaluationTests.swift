import Testing
@testable import Chroma

@MainActor
struct StackEvaluationTests {
  private final class Counter {
    var bodies = 0
    var text = "before"
  }

  private struct Composite: Block {
    let counter: Counter
    var body: some Block {
      counter.bodies += 1
      return Text(counter.text).sizing(x: .grow, y: .grow)
    }
  }

  @Test(arguments: [false, true])
  func resolvesCompositeOncePerOperation(horizontal: Bool) {
    let counter = Counter()
    let child = Composite(counter: counter)
    let stack: any Block = horizontal ? HStack { child } : VStack { child }
    let context = RenderContext(interaction: Interaction())
    let rect = Rect(x: 0, y: 0, width: 400, height: 300)
    _ = BlockEngine.measure(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    counter.bodies = 0
    var first = DrawList()
    context.interaction.beginFrame(input: InputState())
    BlockEngine.draw(stack, into: &first, in: rect, context: context)
    context.interaction.endFrame()
    #expect(counter.bodies == 1)

    counter.text = "after"
    var second = DrawList()
    context.interaction.beginFrame(input: InputState())
    BlockEngine.draw(stack, into: &second, in: rect, context: context)
    context.interaction.endFrame()
    #expect(counter.bodies == 2)
    #expect(second.commands.contains {
      if case .text(_, let text, _, _) = $0 { return text == "after" }
      return false
    })
    #expect(first.commands != second.commands)
  }
}
