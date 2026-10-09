import Testing

@testable import Chroma

@MainActor
struct StackEvaluationTests {
  private final class Counter {
    var bodies = 0
    var text = "before"
  }

  private struct Composite: Block {
    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      buffer.emit(body, context: context.component(Self.self))
    }

    let counter: Counter
    @MainActor var body: some Block {
      counter.bodies += 1
      return Text(counter.text).sizing(x: .grow, y: .grow)
    }
  }

  @Test func engineResolvesCompositeOncePerOperation() {
    let counter = Counter()
    let block = Composite(counter: counter)
    let context = BlockContext()
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    #expect(blockExpandsHorizontally(block))
    #expect(counter.bodies == 1)
    #expect(blockExpandsVertically(block))
    #expect(counter.bodies == 2)
    #expect(measureBlock(block, proposal: rect.size, context: context) == rect.size)
    #expect(counter.bodies == 3)
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(block, context: context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &list, in: rect)
    }
    #expect(counter.bodies == 4)
    #expect(
      list.paintSnapshot.contains {
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
    _ = measureBlock(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    context.interaction.beginFrame(input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(stack, context: context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &list, in: rect)
    }
    context.interaction.endFrame()
    #expect(counter.bodies == 2)
    #expect(
      list.paintSnapshot.contains {
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
    _ = measureBlock(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    context.interaction.beginFrame(input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(stack, context: context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &list, in: rect)
    }
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
    _ = measureBlock(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    counter.bodies = 0
    context.interaction.beginFrame(input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(stack, context: context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &list, in: rect)
    }
    context.interaction.endFrame()
    #expect(counter.bodies == 1)
  }

  @Test func scrollViewSharesContentBetweenMeasurementAndDrawing() {
    let counter = Counter()
    let block = ScrollView { VStack { Composite(counter: counter).sizing(y: .fixed(500)) } }
    let context = BlockContext()
    var list = DrawList()
    context.interaction.beginFrame(input: InputState())
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(block, context: context)
      resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 200, height: 100))
      resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 200, height: 100))
    }
    context.interaction.endFrame()
    #expect(counter.bodies == 1)
  }

  private final class Measurements {
    var proposals: [Size] = []
    var height: Float = 12
  }

  private struct MeasuredLeaf: Block {

    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        expandsHorizontally: expandsHorizontally, expandsVertically: false,
        measure: { sizeThatFits($0, context: context) },
        register: { register(in: $0, context: context) },
        paint: { paint(into: &$0, in: $1, context: context) })
    }

    @MainActor func register(in rect: Rect, context: BlockContext) {}

    let measurements: Measurements
    var focusRule: FocusRule { .decorative }
    var expandsHorizontally: Bool { true }

    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      measurements.proposals.append(proposal)
      return Size(width: proposal.width, height: measurements.height)
    }

    @MainActor func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
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
    var resolvedBuffer = LayoutBuffer()
    let resolved = resolvedBuffer.emit(block, context: context)
    #expect(resolvedBuffer.sizeThatFits(resolved, proposal) == Size(width: 200, height: 12))
    var list = DrawList()
    context.interaction.beginFrame(input: InputState())
    resolvedBuffer.register(resolved, in: Rect(origin: .zero, size: proposal))
    resolvedBuffer.paint(resolved, into: &list, in: Rect(origin: .zero, size: proposal))
    context.interaction.endFrame()
    #expect(measurements.proposals == [proposal, Size(width: 100, height: 100)])

    let narrower = Size(width: 120, height: 100)
    #expect(resolvedBuffer.sizeThatFits(resolved, narrower) == Size(width: 120, height: 12))
    #expect(measurements.proposals.suffix(2) == [narrower, Size(width: 60, height: 100)])

    measurements.height = 30
    measurements.proposals = []
    #expect(measureBlock(block, proposal: proposal, context: context) == Size(width: 200, height: 30))
    #expect(measurements.proposals == [proposal, Size(width: 100, height: 100)])
  }

  @Test func interactiveMeasurementSharesItsIdleBodyAcrossLayoutQueries() {
    let counter = Counter()
    let block = VStack {
      Interactive(action: {}) { _ in Composite(counter: counter).padding(3) }
    }
    _ = measureBlock(block, proposal: Size(width: 200, height: 100), context: BlockContext())
    #expect(counter.bodies == 1)
  }

  @Test(arguments: [4, 8, 16])
  func nestedInteractivePreparationGrowsLinearly(depth: Int) {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    var block: any Block = Text("leaf")
    for _ in 0..<depth {
      let child = block
      block = Interactive(action: {}, content: { _ in TupleBlock(children: [child]) })
    }
    let context = BlockContext()
    let rect = Rect(x: 0, y: 0, width: 200, height: 100)
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(block, context: context)
      #expect(resolvedBuffer.count == 1)
      _ = resolvedBuffer.expandsHorizontally(resolved)
      _ = resolvedBuffer.expandsVertically(resolved)
      _ = resolvedBuffer.sizeThatFits(resolved, rect.size)
      #expect(resolvedBuffer.count == 2 * depth + 1)
      context.interaction.beginFrame(input: InputState())
      resolvedBuffer.register(resolved, in: rect)
      let registered = resolvedBuffer.count
      #expect(registered == 4 * depth + 1)
      var list = DrawList()
      resolvedBuffer.paint(resolved, into: &list, in: rect)
      #expect(resolvedBuffer.count == registered)
      #expect(
        list.paintSnapshot.contains {
          if case .text(_, "leaf", _, _) = $0 { return true }
          return false
        })
      context.interaction.endFrame()
    }
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
        build: { buffer, context in buffer.emit(block, context: context) }, viewport: Size(width: 200, height: 100),
        input: input,
        context: context, onChange: {}
      ).paintSnapshot.compactMap {
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
    _ = measureBlock(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    counter.bodies = 0
    var first = DrawList()
    context.interaction.beginFrame(input: InputState())
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(stack, context: context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &first, in: rect)
    }
    context.interaction.endFrame()
    #expect(counter.bodies == 1)

    counter.text = "after"
    var second = DrawList()
    context.interaction.beginFrame(input: InputState())
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(stack, context: context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &second, in: rect)
    }
    context.interaction.endFrame()
    #expect(counter.bodies == 2)
    #expect(
      second.paintSnapshot.contains {
        if case .text(_, let text, _, _) = $0 { return text == "after" }
        return false
      })
    #expect(first.paintSnapshot != second.paintSnapshot)
  }
}
