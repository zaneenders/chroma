import Testing

@testable import Chroma

@MainActor
struct ReadOnlySelectionTests {
  @MainActor private final class Harness {
    let runtime = WindowRuntime()
    var text = "A👨‍👩‍👧‍👦e\u{301}🇺🇸"
    var visible = true
    var ignored: Bool
    var copyProvider: (@MainActor () -> String?)?
    var selectAllHandler: (@MainActor () -> Bool)?
    var interaction: Interaction { runtime.interaction }
    var cell: Float { runtime.context.fontMetrics.cellAdvance }

    init(ignored: Bool) {
      self.ignored = ignored
      runtime.build = { [unowned self] buffer, context in
        let provider = buffer.customLeaf(
          context: context.keyed("provider"), focusRule: .decorative, measure: { _ in .zero },
          register: { _ in
            context.setCopyTextProvider(self.copyProvider)
            context.setSelectAllHandler(self.selectAllHandler)
          }, paint: { _, _ in })
        var labelContext = context.keyed("label")
        labelContext.navigationIgnored = ignored
        let label =
          visible ? buffer.text(Text(text).selectable(), context: labelContext) : buffer.empty(context: labelContext)
        return buffer.stack([provider, label], axis: .vertical, context: context)
      }
    }

    @discardableResult
    func render(_ input: InputState = InputState()) -> DrawList {
      runtime.render(viewport: Size(width: 200, height: 100), input: input, onChange: {})
    }

    func drag(from: Float, to: Float, release: Bool = true) {
      render(InputState(pointerPosition: Point(x: from * cell, y: 1), pointerDown: true, pointerPressed: true))
      render(InputState(pointerPosition: Point(x: to * cell, y: 1), pointerDown: true))
      if release { render(InputState(pointerPosition: Point(x: to * cell, y: 1), pointerReleased: true)) }
    }
  }

  @Test(arguments: [false, true])
  func pointerSelectionUsesGraphemesAndReverses(ignored: Bool) {
    let harness = Harness(ignored: ignored)
    defer { harness.runtime.reset() }
    harness.render()
    harness.drag(from: 3, to: 1)
    #expect(harness.interaction.copyText() == "👨‍👩‍👧‍👦e\u{301}")
    #expect(harness.interaction.isTextEditing == false)
    #expect(harness.interaction.editingLeaf == nil || !ignored)
    harness.drag(from: 0, to: 30)
    #expect(harness.interaction.copyText() == harness.text)
    harness.drag(from: 3, to: -10)
    #expect(harness.interaction.copyText() == "A👨‍👩‍👧‍👦e\u{301}")
  }

  @Test func pointerOnlySelectionDefersToRegisteredCopyAndSelectAllProviders() {
    let harness = Harness(ignored: true)
    defer { harness.runtime.reset() }
    var selectedAll = 0
    harness.copyProvider = { "provider" }
    harness.selectAllHandler = {
      selectedAll += 1
      return true
    }
    harness.render()
    harness.drag(from: 1, to: 3)
    #expect(harness.interaction.documentCopyText() == "👨‍👩‍👧‍👦e\u{301}")
    #expect(harness.interaction.copyText() == "provider")
    harness.interaction.selectAll(at: .zero)
    #expect(selectedAll == 1)
    #expect(harness.interaction.documentCopyText() == "👨‍👩‍👧‍👦e\u{301}")
    harness.copyProvider = { "" }
    harness.selectAllHandler = { false }
    harness.render()
    #expect(harness.interaction.copyText() == "👨‍👩‍👧‍👦e\u{301}")
    harness.interaction.selectAll(at: Point(x: -50, y: -50))
    #expect(harness.interaction.copyText() == harness.text)
  }

  @Test func focusedReadOnlySelectionPrecedesRegisteredProviders() {
    let harness = Harness(ignored: false)
    defer { harness.runtime.reset() }
    var selectedAll = 0
    harness.copyProvider = { "provider" }
    harness.selectAllHandler = {
      selectedAll += 1
      return true
    }
    harness.render()
    harness.drag(from: 1, to: 3)
    #expect(harness.interaction.copyText() == "👨‍👩‍👧‍👦e\u{301}")
    harness.interaction.selectAll(at: .zero)
    #expect(harness.interaction.copyText() == harness.text)
    #expect(selectedAll == 0)
  }

  @Test(arguments: [false, true])
  func shortenedTextClampsSelectionAndRemovalDoesNotReviveIt(ignored: Bool) {
    let harness = Harness(ignored: ignored)
    defer { harness.runtime.reset() }
    harness.render()
    harness.drag(from: 0, to: 3)
    harness.text = "é"
    harness.render()
    #expect(harness.interaction.copyText() == "é")
    harness.visible = false
    harness.render()
    #expect(harness.interaction.copyText() == nil)
    harness.visible = true
    harness.render()
    #expect(harness.interaction.copyText() == nil)
  }

  @Test func ignoredSelectionKeepsKeyboardFocusAndEndsEditableSelection() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let target = FocusTarget()
    var draft = "draft"
    runtime.build = { buffer, context in
      var ignored = context.keyed("label")
      ignored.navigationIgnored = true
      let label = buffer.text(Text("ignored").selectable(), context: ignored)
      let editor = buffer.group("Editor", context: context.keyed("editor")) { buffer, context in
        buffer.focus(target, context: context) { buffer, context in
          buffer.textEditor(TextEditor(singleLine: true, text: { draft }, onChange: { draft = $0 }), context: context)
        }
      }
      return buffer.stack([label, editor], axis: .vertical, context: context)
    }
    func render(_ input: InputState = InputState()) {
      _ = runtime.render(viewport: Size(width: 250, height: 150), input: input, onChange: {})
    }
    render()
    target.focus(editing: true)
    render()
    #expect(target.isFocused && target.isEditing)
    render(InputState(textEvents: [.selectAll]))
    #expect(runtime.interaction.copyText() == draft)
    let selected = runtime.interaction.selectedLeafID
    let cell = runtime.context.fontMetrics.cellAdvance
    render(InputState(pointerPosition: Point(x: 0, y: 1), pointerDown: true, pointerPressed: true))
    render(InputState(pointerPosition: Point(x: cell * 3, y: 1), pointerReleased: true))
    #expect(runtime.interaction.selectedLeafID == selected)
    #expect(runtime.interaction.editingLeaf == nil)
    #expect(!runtime.context.isSelectingText)
    #expect(runtime.interaction.copyText() == "ign")
    render(InputState(textEvents: [.insert("changed"), .backspace, .selectCaretRight]))
    #expect(draft == "draft")
    #expect(runtime.interaction.copyText() == "ign")
    render(InputState(commands: [.navigation(.stepOut)]))
    #expect(runtime.context.navigationSelectionIsGroup)
    #expect(runtime.interaction.copyText() == "ign")
    target.focus(editing: true)
    render()
    #expect(runtime.interaction.copyText() == nil)
  }

  @Test func documentScopeSkipsPointerOnlyText() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    runtime.build = { buffer, context in
      let first = buffer.text(Text("first").selectable(), context: context.keyed("first"))
      var ignored = context.keyed("ignored")
      ignored.navigationIgnored = true
      let middle = buffer.text(Text("pointer only").selectable(), context: ignored)
      let last = buffer.text(Text("last").selectable(), context: context.keyed("last"))
      return buffer.stack([first, middle, last], axis: .vertical, context: context)
    }
    _ = runtime.render(viewport: Size(width: 250, height: 150), input: InputState(), onChange: {})
    runtime.interaction.selectAll(at: .zero)
    #expect(runtime.interaction.copyText() == "first\nlast")
    #expect(runtime.interaction.registrations.readOnlyTexts.count == 3)
  }

  @Test(arguments: [false, true])
  func virtualEvictionClearsSelectionAndAnActiveDragCannotTransferToAnotherRow(ignored: Bool) {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let controller = ScrollViewController()
    runtime.build = { buffer, context in
      buffer.scrollView(
        ScrollView(
          data: Array(0..<50), rowHeight: 30, controller: controller,
          build: { buffer, context, row in
            var context = context
            context.navigationIgnored = ignored
            return buffer.text(Text("row \(row)").selectable(), context: context)
          }), context: context)
    }
    func render(_ input: InputState = InputState()) {
      _ = runtime.render(viewport: Size(width: 200, height: 60), input: input, onChange: {})
    }
    render()
    render(InputState(pointerPosition: Point(x: 0, y: 1), pointerDown: true, pointerPressed: true))
    render(InputState(pointerPosition: Point(x: 36, y: 1), pointerDown: true))
    #expect(runtime.interaction.copyText() == "row")
    controller.scroll(to: 600)
    render()
    #expect(runtime.interaction.copyText() == nil)
    render(InputState(pointerPosition: Point(x: 48, y: 1), pointerDown: true))
    #expect(runtime.interaction.copyText() == nil)
    render(InputState(pointerPosition: Point(x: 48, y: 1), pointerReleased: true))
    controller.scroll(to: 0)
    render()
    #expect(runtime.interaction.copyText() == nil)
  }

  @Test(arguments: [false, true])
  func ignoredTextRowsKeepKeyboardFallbackAndPointerSelection(variableRows: Bool) throws {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let controller = ScrollViewController()
    var rowIDs: [Int: WidgetID] = [:]
    let buildRow: ScrollView.RowBuilder<Int> = { buffer, context, row in
      rowIDs[row] = context.widgetID
      var ignored = context
      ignored.navigationIgnored = true
      let label = buffer.text(Text("row \(row)").selectable(), context: ignored)
      return buffer.sizing(label, y: .fixed(30), context: context)
    }
    let view =
      variableRows
      ? ScrollView(
        showsIndicator: false, controller: controller,
        rows: (0..<10).map { row in
          ScrollView.Row(id: row) { buffer, context in buildRow(&buffer, context, row) }
        })
      : ScrollView(data: 0..<10, rowHeight: 30, showsIndicator: false, controller: controller, build: buildRow)
    runtime.build = { buffer, context in buffer.scrollView(view, context: context) }
    @discardableResult
    func render(_ input: InputState = InputState()) -> DrawList {
      runtime.render(viewport: Size(width: 200, height: 60), input: input, onChange: {})
    }
    render()
    let firstID = try #require(rowIDs[0])
    let secondID = try #require(rowIDs[1])
    #expect(
      runtime.interaction.tree?.findLeaf(firstID).flatMap { runtime.interaction.tree?.node(at: $0)?.acceptsFocus }
        == true)
    #expect(runtime.interaction.registrations.readOnlyTexts[firstID] == nil)
    render(InputState(commands: [.navigation(.nextFocus)]))
    #expect(runtime.interaction.selectedLeafID == firstID)
    render(InputState(commands: [.navigation(.down)]))
    #expect(runtime.interaction.selectedLeafID == secondID)
    render(InputState(commands: [.navigation(.up)]))
    #expect(runtime.interaction.selectedLeafID == firstID)
    render(InputState(pointerPosition: Point(x: 0, y: 1), pointerDown: true, pointerPressed: true))
    let selected = render(InputState(pointerPosition: Point(x: 36, y: 1), pointerReleased: true))
    #expect(runtime.interaction.copyText() == "row")
    #expect(runtime.interaction.selectedLeafID == firstID)
    #expect(
      selected.paintSnapshot.contains(
        .strokeRect(rect: Rect(x: 0, y: 0, width: 200, height: 30), width: 2, color: runtime.context.theme.focus.ring)))
  }

  @Test func ignoredSelectionStartsOnlyInsideTheCommittedClip() {
    let context = LayoutContext()
    let interaction = context.interaction
    var ignored = context
    ignored.navigationIgnored = true
    let cell = context.fontMetrics.cellAdvance
    let rect = Rect(x: 0, y: 0, width: cell * 6, height: 30)
    interaction.beginFrame(input: InputState())
    context.withInteractionClip(Rect(x: cell, y: 0, width: cell * 2, height: 30)) {
      Text("abcdef").selectable().register(in: rect, context: ignored)
    }
    interaction.endFrame()
    interaction.selectAll(at: Point(x: 1, y: 1))
    #expect(interaction.copyText() == nil)
    interaction.processInput(InputState(pointerPosition: Point(x: 1, y: 1), pointerDown: true, pointerPressed: true))
    interaction.processInput(InputState(pointerPosition: Point(x: cell * 2, y: 1), pointerReleased: true))
    interaction.finishInput()
    #expect(interaction.copyText() == nil)
    interaction.processInput(
      InputState(pointerPosition: Point(x: cell, y: 1), pointerDown: true, pointerPressed: true))
    interaction.processInput(InputState(pointerPosition: Point(x: cell * 8, y: 1), pointerReleased: true))
    interaction.finishInput()
    #expect(interaction.copyText() == "bcdef")
  }

}
