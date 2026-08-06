import Testing

@testable import Chroma

private struct CommandProbe: PrimitiveBlock {
  var name: String
  var size = Size(width: 10, height: 10)
  var color = Color.white

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { size }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    drawList.text(name, at: rect.origin, color: color)
  }
}

private struct CompositeButton: Block {
  var id: WidgetID

  @MainActor var body: some Block {
    Button("Composite", id: id, padding: EdgeInsets()) {}
  }
}

@MainActor
struct RenderingCommandTests {
  private func render(
    _ block: any Block,
    in rect: Rect,
    context: RenderContext,
    input: InputState = InputState()
  ) -> DrawList {
    context.interaction.beginFrame(input: input)
    var list = DrawList()
    BlockEngine.draw(block, into: &list, in: rect, context: context)
    context.interaction.endFrame()
    return list
  }

  @Test func backgroundsPaintBeforeContentAndBordersPaintAfterIt() {
    let rect = Rect(x: 4, y: 6, width: 30, height: 20)
    let background = Color(r: 0.1, g: 0.2, b: 0.3, a: 1)
    let border = Color(r: 0.8, g: 0.7, b: 0.6, a: 1)

    let list = render(
      CommandProbe(name: "content").background(background).border(border, width: 2),
      in: rect,
      context: RenderContext())

    #expect(
      list.commands == [
        .fillRect(rect: rect, color: background),
        .text(position: rect.origin, text: "content", color: .white, scale: 1),
        .strokeRect(rect: rect, width: 2, color: border),
      ])
  }

  @Test func nestedClipsAreBalancedAndPreserveTheirOwnGeometry() {
    let rect = Rect(x: 10, y: 20, width: 50, height: 40)
    let inner = Rect(x: 15, y: 25, width: 40, height: 30)

    let list = render(
      CommandProbe(name: "clipped").clipped().padding(5).clipped(),
      in: rect,
      context: RenderContext())

    #expect(
      list.commands == [
        .pushClip(rect),
        .pushClip(inner),
        .text(position: inner.origin, text: "clipped", color: .white, scale: 1),
        .popClip,
        .popClip,
      ])
  }

  @Test func textSelectionEmitsBackgroundAndTextRunsInPainterOrder() {
    let interaction = Interaction()
    var metrics = FontMetrics()
    metrics.glyphWidth = 8
    metrics.glyphHeight = 14
    metrics.glyphSpacing = 0
    metrics.lineAdvance = 16
    interaction.fontMetrics = metrics
    let context = RenderContext(interaction: interaction, theme: .light)
    let rect = Rect(x: 10, y: 5, width: 32, height: 16)
    let id = WidgetID("render-selection")
    let textColor = Color(r: 1, g: 0, b: 0, a: 1)
    let text = Text("ABCD").foregroundColor(textColor).selectable(id)
    let press = Point(x: 19, y: 6)
    let drag = Point(x: 35, y: 6)

    _ = render(
      text, in: rect, context: context,
      input: InputState(
        pointerPosition: press, pointerPressPosition: press,
        pointerDown: true, pointerPressed: true))
    _ = render(
      text, in: rect, context: context,
      input: InputState(pointerPosition: drag, pointerDown: true))
    let list = render(
      text, in: rect, context: context,
      input: InputState(pointerPosition: drag, pointerDown: true))

    #expect(
      list.commands == [
        .fillRect(
          rect: Rect(x: 18, y: 5, width: 16, height: 16),
          color: ChromaTheme.light.focus.selectionBackground),
        .text(position: Point(x: 10, y: 5), text: "A", color: textColor, scale: 1),
        .text(
          position: Point(x: 18, y: 5), text: "BC",
          color: ChromaTheme.light.focus.selectionForeground, scale: 1),
        .text(position: Point(x: 34, y: 5), text: "D", color: textColor, scale: 1),
      ])
  }

  @Test func zStackKeepsSourceOrderForOverlappingChildren() {
    let rect = Rect(x: 0, y: 0, width: 40, height: 30)
    let first = Color(r: 1, g: 0, b: 0, a: 1)
    let second = Color(r: 0, g: 1, b: 0, a: 1)
    let third = Color(r: 0, g: 0, b: 1, a: 1)

    let list = render(
      ZStack {
        first
        second
        third
      },
      in: rect,
      context: RenderContext())

    #expect(
      list.commands == [
        .fillRect(rect: rect, color: first),
        .fillRect(rect: rect, color: second),
        .fillRect(rect: rect, color: third),
      ])
  }

  @Test func emptyContentEmitsNothingAndNegativeGeometryIsPreserved() {
    let context = RenderContext()
    let negative = Rect(x: 5, y: 7, width: -20, height: -10)
    let fill = Color(r: 0.2, g: 0.3, b: 0.4, a: 1)

    #expect(render(EmptyBlock(), in: .zero, context: context).commands.isEmpty)

    let list = render(
      EmptyBlock().background(fill).border(.yellow, width: 3),
      in: negative,
      context: context)
    #expect(
      list.commands == [
        .fillRect(rect: negative, color: fill),
        .strokeRect(rect: negative, width: 3, color: .yellow),
      ])
  }

  @Test func deeplyNestedModifiersRetainGeometryAndCommandOrder() {
    let rect = Rect(x: 0, y: 0, width: 100, height: 100)
    let background = Color(r: 0.25, g: 0.5, b: 0.75, a: 1)
    var block: any Block = CommandProbe(name: "deep")
    for _ in 0..<32 {
      block = block.padding(1)
    }
    block = block.background(background).border(.yellow, width: 2).clipped()

    let list = render(block, in: rect, context: RenderContext())

    #expect(
      list.commands == [
        .pushClip(rect),
        .fillRect(rect: rect, color: background),
        .text(position: Point(x: 32, y: 32), text: "deep", color: .white, scale: 1),
        .strokeRect(rect: rect, width: 2, color: .yellow),
        .popClip,
      ])
  }

  @Test func scopedThemePropagatesThroughCompositeWidgets() {
    let rect = Rect(x: 3, y: 4, width: 120, height: 28)
    var theme = ChromaTheme.light
    theme.button.idleBackground = Color(r: 0.1, g: 0.15, b: 0.2, a: 1)
    theme.button.foreground = Color(r: 0.9, g: 0.8, b: 0.7, a: 1)
    theme.button.border = Color(r: 0.4, g: 0.5, b: 0.6, a: 1)

    let list = render(
      CompositeButton(id: WidgetID("themed-composite")).chromaTheme(theme),
      in: rect,
      context: RenderContext())

    #expect(
      list.commands == [
        .fillRect(rect: rect, color: theme.button.idleBackground),
        .strokeRect(rect: rect, width: 1, color: theme.button.border),
        .text(
          position: rect.origin, text: "Composite",
          color: theme.button.foreground, scale: 1),
      ])
  }
}
