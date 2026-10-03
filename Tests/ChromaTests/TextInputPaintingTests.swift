import Testing

@testable import Chroma

@MainActor
struct TextInputPaintingTests {
  @Test(arguments: [false, true])
  func backgroundKeepsEditingAndHoverStylesSeparate(editing: Bool) {
    let theme = ChromaTheme.dark
    let style = theme.textEditor
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    var list = DrawList()
    list.textInputBackground(in: rect, style: style, editing: editing, hover: .white)
    #expect(
      list.commands.first
        == .fillRoundedRect(
          rect: rect, radii: CornerRadii(style.cornerRadius),
          color: editing ? style.editingBackground : style.idleBackground))
    #expect(
      list.commands.last
        == .strokeRoundedRect(
          rect: rect, radii: CornerRadii(style.cornerRadius), width: style.borderWidth,
          color: editing ? style.editingBorder : style.border))
    #expect(list.commands.count == (editing ? 2 : 3))
  }

  @Test(arguments: [false, true])
  func focusedTextInputHasBorderWithoutFocusFill(multiline: Bool) throws {
    let context = BlockContext()
    let producer = FrameProducer()
    let content: any Block =
      multiline
      ? TextEditor(text: { "abcd" }, onChange: { _ in })
      : TextEditor(singleLine: true, text: { "abcd" }, onChange: { _ in })
    let size = Size(width: 200, height: 40)
    func render() -> DrawList {
      producer.render(content: content, viewport: size, input: InputState(), context: context, onChange: {})
    }
    _ = render()
    let tree = try #require(context.interaction.tree)
    let id = try #require(tree.firstLeafPath().flatMap { tree.node(at: $0)?.leafID })
    context.interaction.focus(id)
    let focused = render()
    #expect(
      focused.commands.contains {
        if case .strokeRoundedRect(_, _, let width, let color) = $0 {
          return width == 2 && color == context.theme.focus.ring
        }
        return false
      })
    #expect(
      !focused.commands.contains {
        if case .fillRoundedRect(_, _, let color) = $0 {
          return color == HoverStyle.standardTint(in: context.theme)
        }
        return false
      })
  }

  @Test func selectionRepaintsWholeGraphemesThroughAClip() {
    let theme = ChromaTheme.dark
    let origin = Point(x: -12, y: 8)
    let selection = Rect(x: 0, y: 8, width: 24, height: 20)
    let text = "a👨‍👩‍👧‍👦bc"
    var list = DrawList()
    list.textInputLine(
      text, at: origin, scale: 1, foreground: .white, selection: selection, theme: theme.focus)
    #expect(
      list.commands == [
        .text(position: origin, text: text, color: .white, scale: 1),
        .fillRect(rect: selection, color: theme.focus.selectionBackground),
        .pushClip(selection),
        .text(position: origin, text: text, color: theme.focus.selectionForeground, scale: 1),
        .popClip,
      ])
  }

  @Test func draggingBelowShortEditorKeepsViewportAtFirstRow() {
    let context = BlockContext()
    let editor = TextEditor(text: { "short" }, onChange: { _ in })
    context.interaction.beginFrame(
      input: InputState(
        pointerPosition: Point(x: 20, y: 99), pointerPressPosition: Point(x: 20, y: 16),
        pointerDown: true, pointerPressed: true))
    context.interaction.textDragViewportRow = 0
    #expect(context.interaction.isDragging)
    var list = DrawList()
    let resolved = editor.prepareLayout(context: context)
    resolved.register(in: Rect(x: 0, y: 0, width: 200, height: 100))
    resolved.paint(into: &list, in: Rect(x: 0, y: 0, width: 200, height: 100))
    #expect(context.interaction.textDragViewportRow == 0)
  }

  @Test(arguments: [false, true])
  func selectionSuppressesCaretAndPreservesBalancedClips(multiline: Bool) throws {
    let context = BlockContext()
    let producer = FrameProducer()
    let content: any Block =
      multiline
      ? TextEditor(text: { "ab\ncd" }, onChange: { _ in })
      : TextEditor(singleLine: true, text: { "abcd" }, onChange: { _ in })
    func render() -> DrawList {
      producer.render(
        content: content, viewport: Size(width: 200, height: 100), input: InputState(),
        context: context, onChange: {})
    }
    _ = render()
    let tree = try #require(context.interaction.tree)
    let path = try #require(tree.firstLeafPath())
    let id = try #require(tree.node(at: path)?.leafID)
    context.interaction.focus(id, editing: true)
    context.interaction.caretOffset = 1
    let caret = render()
    #expect(
      caret.commands.contains {
        if case .fillRect(_, let color) = $0 { return color == context.theme.textEditor.caret }
        return false
      })
    context.interaction.textSelectionRange = 1..<4
    let selected = render()
    #expect(
      !selected.commands.contains {
        if case .fillRect(_, let color) = $0 { return color == context.theme.textEditor.caret }
        return false
      })
    let highlights = selected.commands.filter {
      if case .fillRect(_, let color) = $0 { return color == context.theme.focus.selectionBackground }
      return false
    }
    #expect(highlights.count == (multiline ? 2 : 1))
    var depth = 0
    for command in selected.commands {
      if case .pushClip = command { depth += 1 }
      if case .popClip = command { depth -= 1 }
      #expect(depth >= 0)
    }
    #expect(depth == 0)
  }
}
