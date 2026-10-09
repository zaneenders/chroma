import Testing

@testable import Chroma

@MainActor
struct TrailingControlsRowTests {
  private final class Recorder { var rects: [Rect] = [] }
  private struct Wrapping: Block {
    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        expandsHorizontally: false, expandsVertically: false,
        measure: { sizeThatFits($0, context: context) },
        register: { register(in: $0, context: context) },
        paint: { paint(into: &$0, in: $1, context: context) })
    }

    @MainActor func register(in rect: Rect, context: BlockContext) {}

    let recorder: Recorder
    var focusRule: FocusRule { .standard }
    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      Size(width: proposal.width, height: proposal.width < 80 ? 40 : 20)
    }
    @MainActor func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      recorder.rects.append(rect)
    }
  }

  @Test func measuresRemainingWidthAndBottomAligns() {
    let recorder = Recorder()
    let row = TrailingControlsRow(spacing: 8) {
      Wrapping(recorder: recorder)
    } controls: {
      Color.white.sizing(x: .fixed(30), y: .fixed(10))
    }
    let interaction = Interaction()
    let context = BlockContext(interaction: interaction)
    #expect(
      measureBlock(row, proposal: Size(width: 100, height: 200), context: context) == Size(width: 100, height: 40))
    #expect(measureBlock(row, proposal: Size(width: 150, height: 200), context: context).height == 20)
    interaction.beginFrame(input: InputState())
    var list = DrawList()
    var resolvedBuffer = LayoutBuffer()
    let resolved = resolvedBuffer.emit(row, context: context)
    resolvedBuffer.register(resolved, in: Rect(x: 10, y: 20, width: 100, height: 60))
    resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 10, y: 20, width: 100, height: 60))
    interaction.endFrame()
    #expect(recorder.rects == [Rect(x: 10, y: 40, width: 62, height: 40)])
    #expect(measureBlock(row, proposal: Size(width: 20, height: 200), context: context).height == 40)
  }
}
