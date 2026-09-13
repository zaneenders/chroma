import Testing

@testable import Chroma

@MainActor
struct StackPlacementTests {
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
    let context = RenderContext()
    let rect = Rect(x: 10, y: 15, width: 200, height: 150)
    let measured = BlockEngine.measure(stack, proposal: rect.size, context: context)
    #expect(measured == (horizontal ? Size(width: 65, height: 50) : Size(width: 40, height: 85)))
    var drawList = DrawList()
    context.interaction.beginFrame(input: InputState())
    BlockEngine.draw(stack, into: &drawList, in: rect, context: context)
    context.interaction.endFrame()
    let rectangles = drawList.commands.compactMap { command -> Rect? in
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
