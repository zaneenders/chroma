import Testing

@testable import Chroma

@MainActor
struct StackPlacementTests {
  private struct Wrapping: PaintableBlock {
    func register(in rect: Rect, context: BlockContext) {}

    var focusRule: FocusRule { .standard }
    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      Size(width: proposal.width, height: proposal.width < 80 ? 40 : 20)
    }
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      list.fillRect(rect, color: .white)
    }
  }

  @Test func growRemeasuresAtRemainingWidthAndBottomAligns() {
    let row = HStack(spacing: 8, alignment: .bottom) {
      Wrapping().sizing(x: .grow)
      Color.black.sizing(x: .fixed(30), y: .fixed(10))
    }
    let context = BlockContext()
    #expect(row.sizeThatFits(Size(width: 100, height: 200), context: context) == Size(width: 100, height: 40))
    #expect(row.sizeThatFits(Size(width: 150, height: 200), context: context).height == 20)
    var list = DrawList()
    context.interaction.beginFrame(input: InputState())
    var resolved = BlockEngine.prepare(row, context: context)
    resolved.register(in: Rect(x: 10, y: 20, width: 100, height: 60))
    resolved.paint(into: &list, in: Rect(x: 10, y: 20, width: 100, height: 60))
    context.interaction.endFrame()
    let rects = list.paintSnapshot.compactMap { command -> Rect? in
      if case .fillRect(let rect, _) = command { return rect }
      return nil
    }
    #expect(rects == [Rect(x: 10, y: 40, width: 62, height: 40), Rect(x: 80, y: 70, width: 30, height: 10)])
  }

  @Test(arguments: [false, true], [false, true])
  func placementPreservesAxisAndReversal(horizontal: Bool, reversed: Bool) {
    let first = Color.white.sizing(x: .fixed(20), y: .fixed(30))
    let second = Color.black.sizing(x: .fixed(40), y: .fixed(50))
    let stack: any Block
    if horizontal {
      let value = HStack(spacing: 5) {
        first
        second
      }
      stack = reversed ? value.reverseLayout() : value
    } else {
      let value = VStack(spacing: 5) {
        first
        second
      }
      stack = reversed ? value.reverseLayout() : value
    }
    let context = BlockContext()
    let rect = Rect(x: 10, y: 15, width: 200, height: 150)
    let measured = BlockEngine.measure(stack, proposal: rect.size, context: context)
    #expect(measured == (horizontal ? Size(width: 65, height: 50) : Size(width: 40, height: 85)))
    var drawList = DrawList()
    context.interaction.beginFrame(input: InputState())
    do {
      var resolved = BlockEngine.prepare(stack, context: context)
      resolved.register(in: rect)
      resolved.paint(into: &drawList, in: rect)
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
