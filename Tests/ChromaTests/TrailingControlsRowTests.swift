import Testing

@testable import Chroma

@MainActor
struct TrailingControlsRowTests {
  private final class Recorder { var rects: [Rect] = [] }
  @Test func measuresRemainingWidthAndBottomAligns() {
    let recorder = Recorder()
    let row: LayoutBuilder = { buffer, context in
      buffer.trailingControls(
        spacing: 8, context: context,
        input: { buffer, context in
          buffer.customLeaf(
            context: context,
            measure: { Size(width: $0.width, height: $0.width < 80 ? 40 : 20) },
            register: { _ in }, paint: { _, rect in recorder.rects.append(rect) })
        },
        controls: { buffer, context in
          let color = buffer.color(.white, context: context)
          return buffer.sizing(color, x: .fixed(30), y: .fixed(10), context: context)
        })
    }
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    #expect(
      measureLayout(row, proposal: Size(width: 100, height: 200), context: context) == Size(width: 100, height: 40))
    #expect(measureLayout(row, proposal: Size(width: 150, height: 200), context: context).height == 20)
    beginTestFrame(interaction, input: InputState())
    var list = DrawList()
    var resolvedBuffer = LayoutBuffer()
    let resolved = row(&resolvedBuffer, context)
    resolvedBuffer.register(resolved, in: Rect(x: 10, y: 20, width: 100, height: 60))
    resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 10, y: 20, width: 100, height: 60))
    interaction.endFrame()
    #expect(recorder.rects == [Rect(x: 10, y: 40, width: 62, height: 40)])
    #expect(measureLayout(row, proposal: Size(width: 20, height: 200), context: context).height == 40)
  }
}
