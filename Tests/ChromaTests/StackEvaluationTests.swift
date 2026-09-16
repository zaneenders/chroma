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

  @Test func engineResolvesCompositeOncePerOperation() {
    let counter = Counter()
    let block = Composite(counter: counter)
    let context = RenderContext()
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    #expect(BlockEngine.expandsHorizontally(block))
    #expect(counter.bodies == 1)
    #expect(BlockEngine.expandsVertically(block))
    #expect(counter.bodies == 2)
    #expect(BlockEngine.measure(block, proposal: rect.size, context: context) == rect.size)
    #expect(counter.bodies == 3)
    var list = DrawList()
    BlockEngine.draw(block, into: &list, in: rect, context: context)
    #expect(counter.bodies == 4)
    #expect(
      list.commands.contains {
        if case .text(_, "before", _, _) = $0 { return true }
        return false
      })
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
    #expect(
      second.commands.contains {
        if case .text(_, let text, _, _) = $0 { return text == "after" }
        return false
      })
    #expect(first.commands != second.commands)
  }
}
