import Testing

@testable import Chroma

@MainActor
struct StackEvaluationTests {
  private final class Counter {
    var bodies = 0
    var text = "before"
  }

  private func composite(_ counter: Counter, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    counter.bodies += 1
    let text = buffer.text(Text(counter.text), context: context)
    return buffer.sizing(text, x: .grow, y: .grow, context: context)
  }

  @Test func directBuilderRunsOncePerOperation() {
    let counter = Counter()
    let block: LayoutBuilder = { buffer, context in composite(counter, into: &buffer, context: context) }
    let context = LayoutContext()
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    #expect(layoutExpandsHorizontally(block))
    #expect(counter.bodies == 1)
    #expect(layoutExpandsVertically(block))
    #expect(counter.bodies == 2)
    #expect(measureLayout(block, proposal: rect.size, context: context) == rect.size)
    #expect(counter.bodies == 3)
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = block(&resolvedBuffer, context)
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
    let stack: LayoutBuilder = { buffer, context in
      let childContext = context.childScope(0)
      let background = buffer.background(
        context: childContext,
        content: { buffer, context in
          let child = composite(counter, into: &buffer, context: context)
          return buffer.padding(child, 4, context: context)
        }, background: { buffer, context in buffer.color(.black, context: context) })
      let clipped = buffer.clip(background, context: childContext)
      let grown = buffer.sizing(clipped, x: .grow, y: .grow, context: childContext)
      return buffer.stack([grown], axis: .horizontal, context: context)
    }
    let context = LayoutContext(interaction: Interaction())
    let rect = Rect(x: 0, y: 0, width: 200, height: 80)

    counter.bodies = 0
    _ = measureLayout(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    beginTestFrame(context.interaction, input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = stack(&resolvedBuffer, context)
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

  @Test func nestedBuilderIsReevaluatedPerOperation() {
    let counter = Counter()
    let stack: LayoutBuilder = { buffer, context in
      let child = composite(counter, into: &buffer, context: context)
      let padded = buffer.padding(child, 3, context: context)
      return buffer.border(padded, color: .black, context: context)
    }
    let context = LayoutContext(interaction: Interaction())
    let rect = Rect(x: 0, y: 0, width: 120, height: 60)
    counter.bodies = 0
    _ = measureLayout(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    beginTestFrame(context.interaction, input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = stack(&resolvedBuffer, context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &list, in: rect)
    }
    context.interaction.endFrame()
    #expect(counter.bodies == 2)
  }

  @Test(arguments: [1, 3, 5])
  func nestedContainersResolveEachBodyOnceWithinATraversal(depth: Int) {
    let counter = Counter()
    var stack: LayoutBuilder = { buffer, context in
      let child = composite(counter, into: &buffer, context: context.childScope(0).withTheme(.dark))
      return buffer.overlay([child], context: context)
    }
    for _ in 0..<depth {
      let child = stack
      stack = { buffer, context in
        let group = buffer.group(context: context.childScope(0)) { buffer, context in
          let horizontalContext = context.childScope(0)
          let verticalContext = horizontalContext.childScope(0)
          let content = child(&buffer, verticalContext.childScope(0))
          let vertical = buffer.stack([content], axis: .vertical, context: verticalContext)
          let padded = buffer.padding(vertical, 3, context: verticalContext)
          return buffer.stack([padded], axis: .horizontal, context: horizontalContext)
        }
        return buffer.stack([group], axis: .vertical, context: context)
      }
    }
    let context = LayoutContext()
    let rect = Rect(x: 0, y: 0, width: 200, height: 100)
    _ = measureLayout(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    counter.bodies = 0
    beginTestFrame(context.interaction, input: InputState())
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = stack(&resolvedBuffer, context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &list, in: rect)
    }
    context.interaction.endFrame()
    #expect(counter.bodies == 1)
  }

  @Test func scrollViewSharesContentBetweenMeasurementAndDrawing() {
    let counter = Counter()
    let scroll = ScrollView { buffer, context in
      let childContext = context.childScope(0)
      let child = composite(counter, into: &buffer, context: childContext)
      let fixed = buffer.sizing(child, y: .fixed(500), context: childContext)
      return buffer.stack([fixed], axis: .vertical, context: context)
    }
    let block: LayoutBuilder = { buffer, context in buffer.scrollView(scroll, context: context) }
    let context = LayoutContext()
    var list = DrawList()
    beginTestFrame(context.interaction, input: InputState())
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = block(&resolvedBuffer, context)
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

  @Test func measurementsAreSharedByProposalAndExpireAfterTraversal() {
    let measurements = Measurements()
    let block: LayoutBuilder = { buffer, context in
      let measured = buffer.customLeaf(
        context: context.childScope(0), focusRule: .decorative,
        expandsHorizontally: true,
        measure: { proposal in
          measurements.proposals.append(proposal)
          return Size(width: proposal.width, height: measurements.height)
        }, register: { _ in }, paint: { list, rect in list.fillRect(rect, color: .black) })
      let spacer = buffer.spacer(context: context.childScope(1))
      return buffer.stack([measured, spacer], axis: .horizontal, context: context)
    }
    let context = LayoutContext()
    let proposal = Size(width: 200, height: 100)
    var resolvedBuffer = LayoutBuffer()
    let resolved = block(&resolvedBuffer, context)
    #expect(resolvedBuffer.sizeThatFits(resolved, proposal) == Size(width: 200, height: 12))
    var list = DrawList()
    beginTestFrame(context.interaction, input: InputState())
    resolvedBuffer.register(resolved, in: Rect(origin: .zero, size: proposal))
    resolvedBuffer.paint(resolved, into: &list, in: Rect(origin: .zero, size: proposal))
    context.interaction.endFrame()
    #expect(measurements.proposals == [proposal, Size(width: 100, height: 100)])

    let narrower = Size(width: 120, height: 100)
    #expect(resolvedBuffer.sizeThatFits(resolved, narrower) == Size(width: 120, height: 12))
    #expect(measurements.proposals.suffix(2) == [narrower, Size(width: 60, height: 100)])

    measurements.height = 30
    measurements.proposals = []
    #expect(measureLayout(block, proposal: proposal, context: context) == Size(width: 200, height: 30))
    #expect(measurements.proposals == [proposal, Size(width: 100, height: 100)])
  }

  @Test func interactiveMeasurementSharesItsIdleBodyAcrossLayoutQueries() {
    let counter = Counter()
    let block: LayoutBuilder = { buffer, context in
      let interactive = buffer.interactive(
        action: {},
        content: { buffer, context, _ in
          let child = composite(counter, into: &buffer, context: context)
          return buffer.padding(child, 3, context: context)
        }, context: context.childScope(0))
      return buffer.stack([interactive], axis: .vertical, context: context)
    }
    _ = measureLayout(block, proposal: Size(width: 200, height: 100), context: LayoutContext())
    #expect(counter.bodies == 1)
  }

  @Test(arguments: [4, 8, 16])
  func nestedInteractivePreparationGrowsLinearly(depth: Int) {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    var block: LayoutBuilder = { buffer, context in buffer.text(Text("leaf"), context: context) }
    for _ in 0..<depth {
      let child = block
      block = { buffer, context in
        buffer.interactive(action: {}, content: { buffer, context, _ in child(&buffer, context) }, context: context)
      }
    }
    let context = LayoutContext()
    let rect = Rect(x: 0, y: 0, width: 200, height: 100)
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = block(&resolvedBuffer, context)
      #expect(resolvedBuffer.count == 1)
      _ = resolvedBuffer.expandsHorizontally(resolved)
      _ = resolvedBuffer.expandsVertically(resolved)
      _ = resolvedBuffer.sizeThatFits(resolved, rect.size)
      #expect(resolvedBuffer.count == depth + 1)
      beginTestFrame(context.interaction, input: InputState(pointerPosition: Point(x: -10, y: -10)))
      resolvedBuffer.register(resolved, in: rect)
      let registered = resolvedBuffer.count
      #expect(registered == depth + 1)
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
    let runtime = WindowRuntime()
    runtime.build = { buffer, context in
      let group = buffer.group(context: context.childScope(0)) { buffer, context in
        buffer.interactive(
          action: { activations += 1 },
          content: { buffer, context, phase in
            let text = buffer.text(Text(String(describing: phase)), context: context)
            return buffer.sizing(text, x: .fixed(100), y: .fixed(40), context: context)
          }, context: context)
      }
      return buffer.stack([group], axis: .vertical, context: context)
    }
    func render(_ input: InputState) -> [String] {
      runtime.render(
        viewport: Size(width: 200, height: 100),
        input: input,
        onChange: {}
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
    let stack: LayoutBuilder = { buffer, context in
      let child = composite(counter, into: &buffer, context: context.childScope(0))
      return buffer.stack([child], axis: horizontal ? .horizontal : .vertical, context: context)
    }
    let context = LayoutContext(interaction: Interaction())
    let rect = Rect(x: 0, y: 0, width: 400, height: 300)
    _ = measureLayout(stack, proposal: rect.size, context: context)
    #expect(counter.bodies == 1)
    counter.bodies = 0
    var first = DrawList()
    beginTestFrame(context.interaction, input: InputState())
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = stack(&resolvedBuffer, context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &first, in: rect)
    }
    context.interaction.endFrame()
    #expect(counter.bodies == 1)

    counter.text = "after"
    var second = DrawList()
    beginTestFrame(context.interaction, input: InputState())
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = stack(&resolvedBuffer, context)
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
