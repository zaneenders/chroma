import Testing

@testable import Chroma

@MainActor
private func commandProbe(_ name: String, into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
  buffer.customLeaf(
    context: context, measure: { _ in Size(width: 10, height: 10) }, register: { _ in },
    paint: { list, rect in list.text(name, at: rect.origin, color: .white) })
}

@MainActor
struct RenderingCommandTests {
  private func render(
    _ build: LayoutBuilder,
    in rect: Rect,
    context: LayoutContext,
    input: InputState = InputState()
  ) -> DrawList {
    beginTestFrame(context.interaction, input: input)
    var list = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = build(&resolvedBuffer, context)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &list, in: rect)
    }
    context.interaction.endFrame()
    return list
  }

  @Test func backgroundsPaintBeforeContentAndBordersPaintAfterIt() {
    let rect = Rect(x: 4, y: 6, width: 30, height: 20)
    let background = Color(r: 0.1, g: 0.2, b: 0.3, a: 1)
    let border = Color(r: 0.8, g: 0.7, b: 0.6, a: 1)

    let list = render(
      { buffer, context in
        let child = buffer.background(
          context: context,
          content: { buffer, context in
            commandProbe("content", into: &buffer, context: context)
          }, background: { buffer, context in buffer.color(background, context: context) })
        return buffer.border(child, color: border, width: 2, context: context)
      },
      in: rect,
      context: LayoutContext())

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
    let context = LayoutContext()

    let outerBackground = render(
      { buffer, context in
        buffer.background(
          context: context,
          content: { buffer, context in
            let child = commandProbe("content", into: &buffer, context: context)
            return buffer.padding(child, 5, context: context)
          }, background: { buffer, context in buffer.color(color, context: context) })
      }, in: rect, context: context)
    let innerBackground = render(
      { buffer, context in
        let child = buffer.background(
          context: context,
          content: { buffer, context in
            commandProbe("content", into: &buffer, context: context)
          }, background: { buffer, context in buffer.color(color, context: context) })
        return buffer.padding(child, 5, context: context)
      }, in: rect, context: context)

    #expect(outerBackground.paintSnapshot.first == .fillRect(rect: rect, color: color))
    #expect(innerBackground.paintSnapshot.first == .fillRect(rect: inset, color: color))
  }

  @Test func nestedClipsAreBalancedAndPreserveTheirOwnGeometry() {
    let rect = Rect(x: 10, y: 20, width: 50, height: 40)
    let inner = Rect(x: 15, y: 25, width: 40, height: 30)

    let list = render(
      { buffer, context in
        let child = commandProbe("clipped", into: &buffer, context: context)
        let clipped = buffer.clip(child, context: context)
        let padded = buffer.padding(clipped, 5, context: context)
        return buffer.clip(padded, context: context)
      },
      in: rect,
      context: LayoutContext())

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
    let context = LayoutContext(interaction: interaction, theme: .dark)
    let rect = Rect(x: 10, y: 5, width: 32, height: 16)
    let id = WidgetID("render-selection")
    let textColor = Color(r: 1, g: 0, b: 0, a: 1)
    let text = Text("ABCD").foregroundColor(textColor).selectable(id)
    let press = Point(x: 19, y: 6)
    let drag = Point(x: 35, y: 6)

    _ = render({ buffer, context in buffer.text(text, context: context) }, in: rect, context: context)
    _ = render(
      { buffer, context in buffer.text(text, context: context) }, in: rect, context: context,
      input: InputState(
        pointerPosition: press, pointerPressPosition: press,
        pointerDown: true, pointerPressed: true))
    _ = render(
      { buffer, context in buffer.text(text, context: context) }, in: rect, context: context,
      input: InputState(pointerPosition: drag, pointerDown: true))
    let list = render(
      { buffer, context in buffer.text(text, context: context) }, in: rect, context: context,
      input: InputState(pointerPosition: drag, pointerDown: true))

    #expect(
      list.paintSnapshot == [
        .fillRect(rect: rect, color: HoverStyle.standardTint(in: .dark, pressed: true)),
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
    let context = LayoutContext(interaction: interaction, theme: .dark)
    let id = WidgetID("text-selection")
    let text = Text("ABC").selectable(id)
    let rect = Rect(x: 4, y: 5, width: 36, height: 16)

    #expect(
      measureLayout({ buffer, context in buffer.text(text, context: context) }, proposal: rect.size, context: context)
        .width
        == 3 * metrics.cellAdvance)

    let press = Point(x: 11, y: 6)
    let drag = Point(x: 17, y: 6)
    _ = render({ buffer, context in buffer.text(text, context: context) }, in: rect, context: context)
    _ = render(
      { buffer, context in buffer.text(text, context: context) }, in: rect, context: context,
      input: InputState(
        pointerPosition: press, pointerPressPosition: press,
        pointerDown: true, pointerPressed: true))
    _ = render(
      { buffer, context in buffer.text(text, context: context) }, in: rect, context: context,
      input: InputState(pointerPosition: drag, pointerDown: true))
    let list = render(
      { buffer, context in buffer.text(text, context: context) }, in: rect, context: context,
      input: InputState(pointerPosition: drag, pointerDown: true))

    #expect(
      list.paintSnapshot == [
        .fillRect(rect: rect, color: HoverStyle.standardTint(in: .dark, pressed: true)),
        .text(position: Point(x: 4, y: 5), text: "ABC", color: .white, scale: 1),
        .fillRect(rect: Rect(x: 10, y: 5, width: 6, height: 16), color: ChromaTheme.dark.focus.selectionBackground),
        .pushClip(Rect(x: 10, y: 5, width: 6, height: 16)),
        .text(position: Point(x: 4, y: 5), text: "ABC", color: ChromaTheme.dark.focus.selectionForeground, scale: 1),
        .popClip,
      ])
  }

  @Test func overlayKeepsSourceOrderForOverlappingChildren() {
    let rect = Rect(x: 0, y: 0, width: 40, height: 30)
    let first = Color(r: 1, g: 0, b: 0, a: 1)
    let second = Color(r: 0, g: 1, b: 0, a: 1)
    let third = Color(r: 0, g: 0, b: 1, a: 1)

    let list = render(
      { buffer, context in
        let children = [first, second, third].enumerated().map { index, color in
          buffer.color(color, context: context.childScope(index))
        }
        return buffer.overlay(children, context: context)
      },
      in: rect,
      context: LayoutContext())

    #expect(
      list.paintSnapshot == [
        .fillRect(rect: rect, color: first),
        .fillRect(rect: rect, color: second),
        .fillRect(rect: rect, color: third),
      ])
  }

  @Test func emptyContentEmitsNothingAndNegativeGeometryIsPreserved() {
    let context = LayoutContext()
    let negative = Rect(x: 5, y: 7, width: -20, height: -10)
    let fill = Color(r: 0.2, g: 0.3, b: 0.4, a: 1)

    #expect(
      render({ buffer, context in buffer.empty(context: context) }, in: .zero, context: context).paintSnapshot.isEmpty)

    let list = render(
      { buffer, context in
        let child = buffer.background(
          context: context, content: { buffer, context in buffer.empty(context: context) },
          background: { buffer, context in buffer.color(fill, context: context) })
        return buffer.border(child, color: .yellow, width: 3, context: context)
      },
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
    let block: LayoutBuilder = { buffer, context in
      let backed = buffer.background(
        context: context,
        content: { buffer, context in
          var child = commandProbe("deep", into: &buffer, context: context)
          for _ in 0..<32 { child = buffer.padding(child, 1, context: context) }
          return child
        }, background: { buffer, context in buffer.color(background, context: context) })
      let bordered = buffer.border(backed, color: .yellow, width: 2, context: context)
      return buffer.clip(bordered, context: context)
    }

    let list = render(block, in: rect, context: LayoutContext())

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
      { buffer, context in
        let child = commandProbe("rounded", into: &buffer, context: context)
        let backed = buffer.roundedBackground(child, color: .black, radii: radii, context: context)
        return buffer.border(backed, color: .yellow, radii: radii, width: 2, context: context)
      },
      in: rect,
      context: LayoutContext())

    #expect(
      list.paintSnapshot == [
        .fillRoundedRect(rect: rect, radii: radii, color: .black),
        .text(position: rect.origin, text: "rounded", color: .white, scale: 1),
        .strokeRoundedRect(rect: rect, radii: radii, width: 2, color: .yellow),
      ])
  }

  @Test func zeroRadiusBorderUsesRectangularCommand() {
    let rect = Rect(x: 2, y: 3, width: 40, height: 24)
    let square = render(
      { buffer, context in
        let child = commandProbe("square", into: &buffer, context: context)
        return buffer.border(child, color: .yellow, width: 2, context: context)
      }, in: rect, context: LayoutContext())
    let rounded = render(
      { buffer, context in
        let child = commandProbe("square", into: &buffer, context: context)
        return buffer.border(child, color: .yellow, radii: CornerRadii(0), width: 2, context: context)
      }, in: rect, context: LayoutContext())
    #expect(rounded.paintSnapshot == square.paintSnapshot)
  }

  @Test(arguments: [CornerRadii.zero, CornerRadii(4)])
  func bordersPreserveContentLayout(radii: CornerRadii) {
    let context = LayoutContext()
    let proposal = Size(width: 100, height: 40)
    let content: LayoutBuilder = { buffer, context in
      let child = commandProbe("layout", into: &buffer, context: context)
      return buffer.sizing(child, x: .grow, context: context)
    }
    let border: LayoutBuilder = { buffer, context in
      let child = content(&buffer, context)
      return buffer.border(child, color: .yellow, radii: radii, width: 3, context: context)
    }
    #expect(
      measureLayout(border, proposal: proposal, context: context)
        == measureLayout(content, proposal: proposal, context: context))
    #expect(layoutExpandsHorizontally(border))
    #expect(!layoutExpandsVertically(border))
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

  @Test func scopedThemePropagatesIntoControls() {
    let rect = Rect(x: 3, y: 4, width: 120, height: 28)
    var theme = ChromaTheme.dark
    theme.button.idleBackground = Color(r: 0.1, g: 0.15, b: 0.2, a: 1)
    theme.button.foreground = Color(r: 0.9, g: 0.8, b: 0.7, a: 1)
    theme.button.border = Color(r: 0.4, g: 0.5, b: 0.6, a: 1)

    let list = render(
      { buffer, context in
        buffer.button(
          Button("Composite", id: WidgetID("themed-composite"), padding: EdgeInsets()) {},
          context: context.withTheme(theme))
      },
      in: rect,
      context: LayoutContext())

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
