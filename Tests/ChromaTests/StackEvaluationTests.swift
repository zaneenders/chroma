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
    let context = BlockContext()
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

  @Test func reusesNestedModifiersWithinEachOperation() {
    let counter = Counter()
    let child = Composite(counter: counter)
      .padding(4)
      .background(Color.black)
      .clipped()
      .sizing(x: .grow, y: .grow)
    let stack = HStack { child }
    let context = BlockContext(interaction: Interaction())
    let rect = Rect(x: 0, y: 0, width: 200, height: 80)

    counter.bodies = 0
    _ = BlockEngine.measure(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    context.interaction.beginFrame(input: InputState())
    var list = DrawList()
    BlockEngine.draw(stack, into: &list, in: rect, context: context)
    context.interaction.endFrame()
    #expect(counter.bodies == 2)
    #expect(
      list.commands.contains {
        if case .text(_, "before", _, _) = $0 { return true }
        return false
      })
  }

  @Test func deferredNestedContentIsReevaluatedPerOperation() {
    let counter = Counter()
    let stack = DeferredBlock { Composite(counter: counter).padding(3).border(.black) }
    let context = BlockContext(interaction: Interaction())
    let rect = Rect(x: 0, y: 0, width: 120, height: 60)
    counter.bodies = 0
    _ = BlockEngine.measure(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    context.interaction.beginFrame(input: InputState())
    var list = DrawList()
    BlockEngine.draw(stack, into: &list, in: rect, context: context)
    context.interaction.endFrame()
    #expect(counter.bodies == 2)
  }

  @Test(arguments: [1, 3, 5])
  func nestedContainersResolveEachBodyOnceWithinATraversal(depth: Int) {
    let counter = Counter()
    var stack: any Block = ZStack {
      ThemeReader { _ in Composite(counter: counter) }.chromaTheme(.dark)
    }
    for _ in 0..<depth {
      stack = VStack {
        Group {
          HStack {
            VStack { stack }.padding(3)
          }
        }
      }
    }
    let context = BlockContext()
    let rect = Rect(x: 0, y: 0, width: 200, height: 100)
    _ = BlockEngine.measure(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    counter.bodies = 0
    context.interaction.beginFrame(input: InputState())
    var list = DrawList()
    BlockEngine.draw(stack, into: &list, in: rect, context: context)
    context.interaction.endFrame()
    #expect(counter.bodies == 1)
  }

  @Test func scrollViewSharesContentBetweenMeasurementAndDrawing() {
    let counter = Counter()
    let block = ScrollView { VStack { Composite(counter: counter).sizing(y: .fixed(500)) } }
    let context = BlockContext()
    var list = DrawList()
    context.interaction.beginFrame(input: InputState())
    BlockEngine.draw(block, into: &list, in: Rect(x: 0, y: 0, width: 200, height: 100), context: context)
    context.interaction.endFrame()
    #expect(counter.bodies == 1)
  }

  private final class Measurements {
    var proposals: [Size] = []
    var height: Float = 12
  }

  private struct MeasuredLeaf: PaintableBlock {
    func register(in rect: Rect, context: BlockContext) {}

    let measurements: Measurements
    var focusRule: FocusRule { .decorative }
    var expandsHorizontally: Bool { true }

    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      measurements.proposals.append(proposal)
      return Size(width: proposal.width, height: measurements.height)
    }

    func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
      drawList.fillRect(rect, color: .black)
    }
  }

  @Test func measurementsAreSharedByProposalAndExpireAfterTraversal() {
    let measurements = Measurements()
    let block = HStack {
      MeasuredLeaf(measurements: measurements)
      Spacer()
    }
    let context = BlockContext()
    let proposal = Size(width: 200, height: 100)
    let resolved = BlockEngine.resolve(block, context: context)
    #expect(resolved.sizeThatFits(proposal) == Size(width: 200, height: 12))
    var list = DrawList()
    context.interaction.beginFrame(input: InputState())
    resolved.draw(into: &list, in: Rect(origin: .zero, size: proposal))
    context.interaction.endFrame()
    #expect(measurements.proposals == [proposal, Size(width: 100, height: 100)])

    let narrower = Size(width: 120, height: 100)
    #expect(resolved.sizeThatFits(narrower) == Size(width: 120, height: 12))
    #expect(measurements.proposals.suffix(2) == [narrower, Size(width: 60, height: 100)])

    measurements.height = 30
    measurements.proposals = []
    #expect(BlockEngine.measure(block, proposal: proposal, context: context) == Size(width: 200, height: 30))
    #expect(measurements.proposals == [proposal, Size(width: 100, height: 100)])
  }

  @Test func interactiveMeasurementSharesItsIdleBodyAcrossLayoutQueries() {
    let counter = Counter()
    let block = VStack {
      Interactive(action: {}) { _ in Composite(counter: counter).padding(3) }
    }
    _ = BlockEngine.measure(block, proposal: Size(width: 200, height: 100), context: BlockContext())
    #expect(counter.bodies == 1)
  }

  @Test func interactiveDrawingUsesCurrentPhaseAfterIdleMeasurement() {
    var activations = 0
    let block = VStack {
      Group {
        Interactive(action: { activations += 1 }) { phase in
          Text(String(describing: phase)).sizing(x: .fixed(100), y: .fixed(40))
        }
      }
    }
    let producer = FrameProducer()
    let context = BlockContext()
    func render(_ input: InputState) -> [String] {
      producer.render(
        content: block, viewport: Size(width: 200, height: 100), input: input,
        context: context, onChange: {}
      ).commands.compactMap {
        if case .text(_, let text, _, _) = $0 { return text }
        return nil
      }
    }
    #expect(render(InputState(pointerPosition: Point(x: -10, y: -10))) == ["idle"])
    let point = Point(x: 5, y: 5)
    #expect(render(InputState(pointerPosition: point)) == ["hovered"])
    #expect(render(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true)) == ["pressed"])
    #expect(render(InputState(pointerPosition: point, pointerReleased: true)) == ["hovered"])
    #expect(activations == 1)
  }

  @Test(arguments: [false, true])
  func resolvesCompositeOncePerOperation(horizontal: Bool) {
    let counter = Counter()
    let child = Composite(counter: counter)
    let stack: any Block = horizontal ? HStack { child } : VStack { child }
    let context = BlockContext(interaction: Interaction())
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
