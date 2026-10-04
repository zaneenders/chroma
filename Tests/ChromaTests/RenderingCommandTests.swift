import Testing

@testable import Chroma

private struct CommandProbe: PaintableBlock {
  func register(in rect: Rect, context: BlockContext) {}

  var name: String
  var size = Size(width: 10, height: 10)
  var color = Color.white

  var focusRule: FocusRule { .standard }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { size }

  func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
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
    context: BlockContext,
    input: InputState = InputState()
  ) -> DrawList {
    context.interaction.beginFrame(input: input)
    var list = DrawList()
    do {
      let resolved = BlockEngine.prepare(block, context: context)
      resolved.register(in: rect)
      resolved.paint(into: &list, in: rect)
    }
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
      context: BlockContext())

    #expect(
      list.paintSnapshot == [
        .fillRect(rect: rect, color: background),
        .text(position: rect.origin, text: "content", color: .white, scale: 1),
        .strokeRect(rect: rect, width: 2, color: border),
      ])
  }

  @Test func modifierOrderChangesBackgroundGeometry() {
    let rect = Rect(x: 0, y: 0, width: 30, height: 20)
    let inset = Rect(x: 5, y: 5, width: 20, height: 10)
    let color = Color.black
    let context = BlockContext()

    let outerBackground = render(
      CommandProbe(name: "content").padding(5).background(color), in: rect, context: context)
    let innerBackground = render(
      CommandProbe(name: "content").background(color).padding(5), in: rect, context: context)

    #expect(outerBackground.paintSnapshot.first == .fillRect(rect: rect, color: color))
    #expect(innerBackground.paintSnapshot.first == .fillRect(rect: inset, color: color))
  }

  @Test func nestedClipsAreBalancedAndPreserveTheirOwnGeometry() {
    let rect = Rect(x: 10, y: 20, width: 50, height: 40)
    let inner = Rect(x: 15, y: 25, width: 40, height: 30)

    let list = render(
      CommandProbe(name: "clipped").clipped().padding(5).clipped(),
      in: rect,
      context: BlockContext())

    #expect(
      list.paintSnapshot == [
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
    metrics.cellAdvance = 8
    metrics.lineAdvance = 16
    interaction.fontMetrics = metrics
    let context = BlockContext(interaction: interaction, theme: .dark)
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
      list.paintSnapshot == [
        .fillRect(rect: rect, color: HoverStyle.standardTint(in: .dark)),
        .text(position: Point(x: 10, y: 5), text: "ABCD", color: textColor, scale: 1),
        .fillRect(rect: Rect(x: 18, y: 5, width: 16, height: 16), color: ChromaTheme.dark.focus.selectionBackground),
        .pushClip(Rect(x: 18, y: 5, width: 16, height: 16)),
        .text(position: Point(x: 10, y: 5), text: "ABCD", color: ChromaTheme.dark.focus.selectionForeground, scale: 1),
        .popClip,
      ])
  }

  @Test func textUsesSameAdvanceForMeasurementAndSelection() {
    let interaction = Interaction()
    var metrics = FontMetrics()
    metrics.glyphWidth = 10
    metrics.cellAdvance = 6
    metrics.lineAdvance = 16
    interaction.fontMetrics = metrics
    let context = BlockContext(interaction: interaction, theme: .dark)
    let id = WidgetID("text-selection")
    let text = Text("ABC").selectable(id)
    let rect = Rect(x: 4, y: 5, width: 36, height: 16)

    #expect(
      BlockEngine.measure(text, proposal: rect.size, context: context).width
        == 3 * metrics.cellAdvance)

    let press = Point(x: 11, y: 6)
    let drag = Point(x: 17, y: 6)
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
      list.paintSnapshot == [
        .fillRect(rect: rect, color: HoverStyle.standardTint(in: .dark)),
        .text(position: Point(x: 4, y: 5), text: "ABC", color: .white, scale: 1),
        .fillRect(rect: Rect(x: 10, y: 5, width: 6, height: 16), color: ChromaTheme.dark.focus.selectionBackground),
        .pushClip(Rect(x: 10, y: 5, width: 6, height: 16)),
        .text(position: Point(x: 4, y: 5), text: "ABC", color: ChromaTheme.dark.focus.selectionForeground, scale: 1),
        .popClip,
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
      context: BlockContext())

    #expect(
      list.paintSnapshot == [
        .fillRect(rect: rect, color: first),
        .fillRect(rect: rect, color: second),
        .fillRect(rect: rect, color: third),
      ])
  }

  @Test func emptyContentEmitsNothingAndNegativeGeometryIsPreserved() {
    let context = BlockContext()
    let negative = Rect(x: 5, y: 7, width: -20, height: -10)
    let fill = Color(r: 0.2, g: 0.3, b: 0.4, a: 1)

    #expect(render(EmptyBlock(), in: .zero, context: context).paintSnapshot.isEmpty)

    let list = render(
      EmptyBlock().background(fill).border(.yellow, width: 3),
      in: negative,
      context: context)
    #expect(
      list.paintSnapshot == [
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

    let list = render(block, in: rect, context: BlockContext())

    #expect(
      list.paintSnapshot == [
        .pushClip(rect),
        .fillRect(rect: rect, color: background),
        .text(position: Point(x: 32, y: 32), text: "deep", color: .white, scale: 1),
        .strokeRect(rect: rect, width: 2, color: .yellow),
        .popClip,
      ])
  }

  @Test func roundedModifiersPaintInPainterOrder() {
    let rect = Rect(x: 2, y: 3, width: 40, height: 24)
    let radii = CornerRadii(topLeft: 2, topRight: 4, bottomRight: 6, bottomLeft: 8)

    let list = render(
      CommandProbe(name: "rounded")
        .roundedBackground(.black, radii: radii)
        .roundedBorder(.yellow, radii: radii, width: 2),
      in: rect,
      context: BlockContext())

    #expect(
      list.paintSnapshot == [
        .fillRoundedRect(rect: rect, radii: radii, color: .black),
        .text(position: rect.origin, text: "rounded", color: .white, scale: 1),
        .strokeRoundedRect(rect: rect, radii: radii, width: 2, color: .yellow),
      ])
  }

  @Test func zeroRadiusBorderUsesRectangularCommand() {
    let rect = Rect(x: 2, y: 3, width: 40, height: 24)
    let content = CommandProbe(name: "square")
    let square = render(
      content.border(.yellow, width: 2), in: rect, context: BlockContext())
    let rounded = render(
      content.roundedBorder(.yellow, radius: 0, width: 2), in: rect, context: BlockContext())
    #expect(rounded.paintSnapshot == square.paintSnapshot)
  }

  @Test(arguments: [CornerRadii.zero, CornerRadii(4)])
  func bordersPreserveContentLayout(radii: CornerRadii) {
    let context = BlockContext()
    let proposal = Size(width: 100, height: 40)
    let content = CommandProbe(name: "layout").sizing(x: .grow)
    let border = content.roundedBorder(.yellow, radii: radii, width: 3)
    #expect(
      BlockEngine.measure(border, proposal: proposal, context: context)
        == BlockEngine.measure(content, proposal: proposal, context: context))
    #expect(BlockEngine.expandsHorizontally(border))
    #expect(!BlockEngine.expandsVertically(border))
  }

  @Test func cornerRadiiNormalizeWithoutOverlapping() {
    let normalized = CornerRadii(
      topLeft: 30, topRight: 30, bottomRight: -4, bottomLeft: 10
    ).normalized(for: Size(width: 40, height: 20))

    #expect(
      normalized
        == CornerRadii(
          topLeft: 15, topRight: 15, bottomRight: 0, bottomLeft: 5))
  }

  @Test func scopedThemePropagatesThroughCompositeWidgets() {
    let rect = Rect(x: 3, y: 4, width: 120, height: 28)
    var theme = ChromaTheme.dark
    theme.button.idleBackground = Color(r: 0.1, g: 0.15, b: 0.2, a: 1)
    theme.button.foreground = Color(r: 0.9, g: 0.8, b: 0.7, a: 1)
    theme.button.border = Color(r: 0.4, g: 0.5, b: 0.6, a: 1)

    let list = render(
      CompositeButton(id: WidgetID("themed-composite")).chromaTheme(theme),
      in: rect,
      context: BlockContext())

    #expect(
      list.paintSnapshot == [
        .fillRoundedRect(
          rect: rect, radii: CornerRadii(theme.button.cornerRadius),
          color: theme.button.idleBackground),
        .strokeRoundedRect(
          rect: rect, radii: CornerRadii(theme.button.cornerRadius),
          width: theme.button.borderWidth, color: theme.button.border),
        .text(
          position: rect.origin, text: "Composite",
          color: theme.button.foreground, scale: 1),
      ])
  }
}
