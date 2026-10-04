import Testing

@testable import Chroma

@MainActor
struct PlainTextFastPathTests {
  private let rect = Rect(x: 5, y: 7, width: 200, height: 100)

  @Test(arguments: ["", "label", "first\nsecond\n", "a\r\nb", "é 👩🏽‍💻\n世界"])
  func plainTextPreservesCommandsAndMeasurement(content: String) {
    let context = BlockContext(textScale: 1.5)
    let text = Text(content).fontScale(2).foregroundColor(.black)
    let resolved = text.prepareLayout(context: context)
    #expect(resolved.sizeThatFits(rect.size) == context.fontMetrics.measure(content, scale: 3))
    var expected = DrawList()
    for (row, line) in TextLayout(content).lines.enumerated() {
      expected.text(
        line.text,
        at: Point(x: rect.minX, y: rect.minY + Float(row) * context.fontMetrics.lineAdvance * 3),
        color: .black, scale: 3)
    }
    var prepared = DrawList()
    resolved.paint(into: &prepared, in: rect)
    var directPaint = DrawList()
    text.paint(into: &directPaint, in: rect, context: context)
    #expect(prepared.paintSnapshot == expected.paintSnapshot)
    #expect(directPaint.paintSnapshot == expected.paintSnapshot)
    #expect(context.interaction.tree == nil)
    #expect(context.interaction.builderRoot == nil)
    #expect(context.interaction.building.inputHandlers.isEmpty)
    #expect(context.interaction.building.buttonActions.isEmpty)
    #expect(context.interaction.editingLeaf == nil)
  }

  @Test(arguments: [false, true], [false, true])
  func plainTextPreservesFocusAndPaintIsolation(claimed: Bool, ignored: Bool) {
    var context = BlockContext()
    context.focusLeafClaimed = claimed
    context.navigationIgnored = ignored
    let resolved = Text("label").prepareLayout(context: context)
    context.interaction.beginFrame(input: InputState())
    resolved.register(in: rect)
    let leaves = context.interaction.builderRoot?.children.count
    #expect(leaves == (claimed || ignored ? 0 : 1))
    context.interaction.selectedLeafID = context.widgetID
    var first = DrawList()
    resolved.paint(into: &first, in: rect)
    var second = DrawList()
    resolved.paint(into: &second, in: rect)
    #expect(first.paintSnapshot == second.paintSnapshot)
    #expect(first.paintSnapshot.count == (claimed || ignored ? 1 : 2))
    if !claimed, !ignored {
      #expect(first.paintSnapshot.last == .strokeRect(rect: rect, width: 2, color: context.theme.focus.ring))
    }
    #expect(context.interaction.builderRoot?.children.count == leaves)
    #expect(context.interaction.building.inputHandlers.isEmpty)
    #expect(context.interaction.editingLeaf == nil)
    context.interaction.endFrame()
  }

  @Test func plainTextShapesOnlyWhenPaintedAndCountsEachLayout() {
    let context = BlockContext()
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    PipelineMetrics.reset()
    let resolved = Text("plain").prepareLayout(context: context)
    _ = resolved.sizeThatFits(rect.size)
    context.interaction.beginFrame(input: InputState())
    resolved.register(in: rect)
    #expect(PipelineMetrics.snapshot.textLayouts == 0)
    #expect(PipelineMetrics.snapshot.paints == 0)
    var list = DrawList()
    resolved.paint(into: &list, in: rect)
    #expect(PipelineMetrics.snapshot.textLayouts == 1)
    resolved.paint(into: &list, in: rect)
    #expect(PipelineMetrics.snapshot.textLayouts == 2)
    context.interaction.endFrame()
  }
}
