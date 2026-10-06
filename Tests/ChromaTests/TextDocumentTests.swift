import Testing

@testable import Chroma

@MainActor
struct TextDocumentTests {
  private let owner = TextID("document")
  private let viewport = Size(width: 120, height: 40)

  private func document(_ texts: [String], revision: UInt64 = 0, id: TextID? = nil) -> TextDocument {
    TextDocument(
      id: id ?? owner, revision: revision,
      runs: texts.enumerated().map {
        .init(id: TextID($0.offset), text: $0.element, separator: "\n\n")
      })
  }

  @Test func copyUsesCompleteRunsAndExplicitSeparatorsAtCharacterBoundaries() {
    let document = document(["A👨‍👩‍👧‍👦", "e\u{301}", "🇺🇸Z"])
    let selection = TextDocument.Selection(
      document: owner, anchor: .init(run: TextID(2), offset: 1), active: .init(run: TextID(0), offset: 1))
    #expect(document.text(in: selection) == "👨‍👩‍👧‍👦\n\ne\u{301}\n\n🇺🇸")
    #expect(document.range(in: TextID(1), selection: selection) == 0..<1)
    #expect(
      document.text(in: .init(document: owner, anchor: selection.anchor, active: .init(run: TextID(0), offset: -1)))
        == nil)
  }

  @Test func backwardSelectionSurvivesVirtualizationAndReversesWithoutMovingAnchor() throws {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let controller = ScrollViewController()
    let document = document((0..<40).map { "row \($0)" })
    runtime.content = ScrollView(data: 0..<40, rowHeight: 20, controller: controller) { index in
      Text(document.runs[index].text).selectable().textRun(TextID(index))
    }.textDocument(document)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    let anchor = TextDocument.Position(run: TextID(30), offset: 4)
    runtime.context.selection.select(.init(document: owner, anchor: anchor, active: .init(run: TextID(0), offset: 1)))
    let expected = document.text(in: try #require(runtime.context.selection.selection))
    controller.scroll(to: 200)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(runtime.interaction.registrations.readOnlyTexts.count < document.runs.count)
    #expect(
      runtime.interaction.registrations.readOnlyTexts.values.allSatisfy {
        $0.reference.run != TextID(0) && $0.reference.run != TextID(30)
      })
    #expect(runtime.interaction.copyText() == expected)
    #expect(
      runtime.interaction.textLeafIDs(in: runtime.interaction.tree).allSatisfy {
        runtime.interaction.documentRange(for: $0)?.isEmpty == false
      })
    runtime.handleInput(InputState(textEvents: [.selectCaretRight, .selectCaretRight]))
    #expect(runtime.context.selection.selection?.anchor == anchor)
    #expect(runtime.context.selection.selection?.active == .init(run: TextID(0), offset: 3))
    runtime.handleInput(InputState(textEvents: [.selectCaretLeft]))
    #expect(runtime.context.selection.selection?.anchor == anchor)
    #expect(runtime.context.selection.selection?.active == .init(run: TextID(0), offset: 2))
    _ = runtime.renderScheduled(.content, viewport: Size(width: 36, height: 60), onChange: {})
    #expect(runtime.context.selection.selection?.anchor == anchor)
  }

  @Test func selectAllIncludesOffscreenRunsAndCrossRunMovementDispatchesOnce() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let document = document(["ab", "cd", "ef", "gh", "ij"])
    runtime.content = ScrollView(data: 0..<5, rowHeight: 20, controller: ScrollViewController()) { index in
      Text(document.runs[index].text).selectable().textRun(TextID(index))
    }.textDocument(document)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    runtime.interaction.selectAll(at: .zero)
    #expect(runtime.interaction.copyText() == "ab\n\ncd\n\nef\n\ngh\n\nij")
    let anchor = TextDocument.Position(run: TextID(0), offset: 1)
    runtime.context.selection.select(.init(document: owner, anchor: anchor, active: anchor))
    runtime.handleInput(InputState(textEvents: [.selectCaretRight, .selectCaretRight, .selectCaretRight]))
    #expect(runtime.context.selection.selection?.anchor == anchor)
    #expect(runtime.context.selection.selection?.active == .init(run: TextID(1), offset: 1))
    #expect(runtime.interaction.copyText() == "b\n\nc")
  }

  @Test func deletionRevisionAndSessionReplacementClearRatherThanClampSelection() {
    let selection = TextSelectionManager()
    let original = document(["abcd", "efgh"])
    let range = TextDocument.Selection(
      document: owner, anchor: .init(run: TextID(0), offset: 1), active: .init(run: TextID(1), offset: 3))
    for replacement in [
      document(["abcd"]), document(["wxyz", "efgh"]), document(["abcd", "efgh"], revision: 1),
      document(["abcd", "efgh"], id: TextID("replacement")),
    ] {
      selection.install([owner: original])
      selection.select(range)
      selection.install([replacement.id: replacement])
      #expect(selection.selection == nil)
      #expect(selection.selectedText() == nil)
    }
  }

  @Test func editorSessionReplacementClearsDocumentSelection() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let editor = FocusTarget()
    runtime.content = VStack {
      Text("read only").selectable()
      TextEditor(text: { "draft" }, onChange: { _ in }).focusTarget(editor)
    }
    _ = runtime.renderScheduled(.content, viewport: Size(width: 200, height: 200), onChange: {})
    runtime.interaction.selectAll(at: .zero)
    #expect(runtime.interaction.copyText() == "read only")
    editor.focus(editing: true)
    runtime.handleInput(InputState())
    #expect(runtime.context.selection.selection == nil)
    #expect(runtime.interaction.copyText() == nil)
  }

  @Test func visibleFragmentsMapToOneRunAndPointerDragKeepsItsAnchor() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let document = TextDocument(id: owner, runs: [.init(id: TextID(0), text: "abcdef")])
    runtime.content = VStack(spacing: 0) {
      Text("abc").selectable().textRun(TextID(0))
      Text("def").selectable().textRun(TextID(0), offset: 3)
    }.textDocument(document)
    _ = runtime.renderScheduled(.content, viewport: Size(width: 200, height: 100), onChange: {})
    let cell = runtime.context.fontMetrics.cellAdvance
    let line = runtime.context.fontMetrics.lineAdvance
    runtime.handleInput(InputState(pointerPosition: Point(x: cell, y: 1), pointerDown: true, pointerPressed: true))
    runtime.handleInput(InputState(pointerPosition: Point(x: cell * 2, y: line + 1), pointerDown: true))
    #expect(runtime.interaction.copyText() == "bcde")
    runtime.handleInput(InputState(pointerPosition: Point(x: cell, y: line + 1), pointerReleased: true))
    #expect(runtime.context.selection.selection?.anchor == .init(run: TextID(0), offset: 1))
    #expect(runtime.interaction.copyText() == "bcd")
  }
  @Test func focusChangesDoNotReplaceDocumentOwnershipAndRootReplacementClearsIt() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let document = document(["abcd"])
    let button = FocusTarget()
    runtime.content = VStack {
      Text("abcd").selectable().textRun(TextID(0))
      Button("other focus") {}.focusTarget(button)
    }.textDocument(document)
    _ = runtime.renderScheduled(.content, viewport: Size(width: 200, height: 200), onChange: {})
    let selection = TextDocument.Selection(
      document: owner, anchor: .init(run: TextID(0), offset: 1), active: .init(run: TextID(0), offset: 3))
    runtime.context.selection.select(selection)
    button.focus()
    runtime.handleInput(InputState())
    #expect(button.isFocused)
    #expect(runtime.context.selection.selection == selection)
    #expect(runtime.interaction.copyText() == "bc")
    runtime.content = Text("replacement")
    #expect(runtime.context.selection.selection == nil)
    #expect(runtime.interaction.copyText() == nil)
  }

  @Test func deletedOffscreenEndpointClearsDuringPresentation() {
    final class Model { var includesLast = true }
    let model = Model()
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let controller = ScrollViewController()
    runtime.content = DeferredBlock {
      let document = document(model.includesLast ? ["one", "two", "three"] : ["one", "two"])
      return ScrollView(data: 0..<document.runs.count, rowHeight: 40, controller: controller) { index in
        Text(document.runs[index].text).selectable().textRun(TextID(index))
      }.textDocument(document)
    }
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    runtime.context.selection.select(
      .init(
        document: owner, anchor: .init(run: TextID(0), offset: 1), active: .init(run: TextID(2), offset: 2)))
    model.includesLast = false
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(runtime.context.selection.selection == nil)
    #expect(runtime.interaction.copyText() == nil)
  }

}
