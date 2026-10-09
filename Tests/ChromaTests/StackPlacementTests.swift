import Testing

@testable import Chroma

@MainActor
struct StackPlacementTests {
  @Test func growMeasuresAtRemainingWidthAndBottomAligns() {
    let row: LayoutBuilder = { buffer, context in
      let firstContext = context.childScope(0)
      let first = buffer.customLeaf(
        context: firstContext,
        measure: { Size(width: $0.width, height: $0.width < 80 ? 40 : 20) },
        register: { _ in }, paint: { $0.fillRect($1, color: .white) })
      let input = buffer.sizing(first, x: .grow, context: firstContext)
      let secondContext = context.childScope(1)
      let second = buffer.color(.black, context: secondContext)
      let controls = buffer.sizing(second, x: .fixed(30), y: .fixed(10), context: secondContext)
      return buffer.stack([input, controls], axis: .horizontal, spacing: 8, bottomAligned: true, context: context)
    }
    let context = LayoutContext()
    #expect(
      measureLayout(row, proposal: Size(width: 100, height: 200), context: context) == Size(width: 100, height: 40))
    #expect(measureLayout(row, proposal: Size(width: 150, height: 200), context: context).height == 20)
    var list = DrawList()
    beginTestFrame(context.interaction, input: InputState())
    var resolvedBuffer = LayoutBuffer()
    let resolved = row(&resolvedBuffer, context)
    resolvedBuffer.register(resolved, in: Rect(x: 10, y: 20, width: 100, height: 60))
    resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 10, y: 20, width: 100, height: 60))
    context.interaction.endFrame()
    let rects = list.paintSnapshot.compactMap { command -> Rect? in
      if case .fillRect(let rect, _) = command { return rect }
      return nil
    }
    #expect(rects == [Rect(x: 10, y: 40, width: 62, height: 40), Rect(x: 80, y: 70, width: 30, height: 10)])
  }

  @Test func growSkipsDiscardedProposalAndPaintingOnlyUsesRegisteredRectangles() {
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    var proposals: [Size] = []
    var registered: [Rect] = []
    var painted: [Rect] = []
    let grow = buffer.customLeaf(
      context: context.childScope(0), focusRule: .decorative, expandsHorizontally: true,
      measure: {
        proposals.append($0)
        return Size(width: $0.width, height: 12)
      },
      register: { registered.append($0) }, paint: { _, rect in painted.append(rect) })
    let fixed = buffer.sizing(buffer.empty(context: context.childScope(1)), x: .fixed(20), context: context)
    let root = buffer.stack([grow, fixed], axis: .horizontal, spacing: 5, context: context)
    let rect = Rect(x: 20, y: 30, width: 100, height: 60)
    beginTestFrame(context.interaction, input: InputState())
    buffer.register(root, in: rect)
    context.interaction.endFrame()
    #expect(proposals == [Size(width: 75, height: 60)])
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    var list = DrawList()
    buffer.paint(root, into: &list, in: rect)
    #expect(painted == registered)
    #expect(painted == [Rect(x: 20, y: 30, width: 75, height: 12)])
    #expect(PipelineMetrics.snapshot.measurements == 0)
  }

  @Test(arguments: [false, true])
  func focusDoesNotChangeSpacerCrossAxis(horizontal: Bool) {
    let target = FocusTarget()
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    let spacer = buffer.focus(target, context: context.childScope(0)) { buffer, context in
      buffer.spacer(context: context)
    }
    #expect(buffer.count == 1)
    let fixed = buffer.sizing(
      buffer.empty(context: context.childScope(1)), x: .fixed(20), y: .fixed(12), context: context)
    let root = buffer.stack([spacer, fixed], axis: horizontal ? .horizontal : .vertical, context: context)
    #expect(
      buffer.sizeThatFits(root, Size(width: 100, height: 60))
        == (horizontal ? Size(width: 100, height: 12) : Size(width: 20, height: 60)))
  }

  @Test(arguments: [false, true], [false, true])
  func placementPreservesAxisAndReversal(horizontal: Bool, reversed: Bool) {
    let stack: LayoutBuilder = { buffer, context in
      let firstContext = context.childScope(0)
      let first = buffer.color(.white, context: firstContext)
      let firstSized = buffer.sizing(first, x: .fixed(20), y: .fixed(30), context: firstContext)
      let secondContext = context.childScope(1)
      let second = buffer.color(.black, context: secondContext)
      let secondSized = buffer.sizing(second, x: .fixed(40), y: .fixed(50), context: secondContext)
      return buffer.stack(
        [firstSized, secondSized], axis: horizontal ? .horizontal : .vertical,
        spacing: 5, reversed: reversed, context: context)
    }
    let context = LayoutContext()
    let rect = Rect(x: 10, y: 15, width: 200, height: 150)
    let measured = measureLayout(stack, proposal: rect.size, context: context)
    #expect(measured == (horizontal ? Size(width: 65, height: 50) : Size(width: 40, height: 85)))
    var drawList = DrawList()
    beginTestFrame(context.interaction, input: InputState())
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = stack(&resolvedBuffer, context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &drawList, in: rect)
    }
    context.interaction.endFrame()
    let rectangles = drawList.paintSnapshot.compactMap { command -> Rect? in
      if case .fillRect(let rect, _) = command { return rect }
      return nil
    }
    let expected: [Rect]
    if horizontal {
      expected = [
        Rect(x: reversed ? 190 : 10, y: 15, width: 20, height: 30),
        Rect(x: reversed ? 145 : 35, y: 15, width: 40, height: 50),
      ]
    } else {
      expected = [
        Rect(x: 10, y: reversed ? 135 : 15, width: 20, height: 30),
        Rect(x: 10, y: reversed ? 80 : 50, width: 40, height: 50),
      ]
    }
    #expect(rectangles == expected)
  }
}
