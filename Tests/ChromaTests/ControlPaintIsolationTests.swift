import Testing

@testable import Chroma

@MainActor
struct ControlPaintIsolationTests {
  private let rect = Rect(x: 0, y: 0, width: 200, height: 80)

  @Test func paintingControlsWithoutAnUpdateDoesNotCreateInteractionState() {
    var actions = 0
    var changes = 0
    let controls: [any Block] = [
      Button("Action", action: { actions += 1 }),
      Interactive(action: { actions += 1 }, content: { phase in Text("\(phase)") }),
      TextEditor(text: { "draft" }, onChange: { _ in changes += 1 }),
      Text("selectable").selectable(),
    ]
    for control in controls {
      let context = BlockContext()
      var list = DrawList()
      BlockEngine.resolve(control, context: context).paint(into: &list, in: rect)
      #expect(!list.commands.isEmpty)
      #expect(context.interaction.tree == nil)
      #expect(context.interaction.builderRoot == nil)
      #expect(context.interaction.building.inputHandlers.isEmpty)
      #expect(context.interaction.building.buttonActions.isEmpty)
      #expect(context.interaction.building.focusTargets.isEmpty)
      #expect(context.interaction.textSelection.layoutRegistry.entry(at: Point(x: 10, y: 10)) == nil)
      #expect(context.interaction.editingLeaf == nil)
    }
    #expect(actions == 0)
    #expect(changes == 0)
  }

  @Test func visualStateDoesNotExposeActivationEdgesOrConsumePendingFocus() {
    let context = BlockContext()
    let id = context.widgetID
    context.interaction.selectedLeafID = id
    context.interaction.activatedLeaf = id
    context.interaction.activatePending = true
    context.interaction.beginEditing(id, caretOffset: 8)
    context.interaction.textSelectionRange = 2..<8
    let generation = context.interaction.editingSessionGeneration
    #expect(context.buttonVisualState().focused)
    #expect(!context.buttonVisualState().clicked)
    #expect(context.textInputVisualState().caretOffset == 8)
    #expect(context.textInputVisualState().selectionRange == 2..<8)
    #expect(context.interaction.activatePending)
    #expect(context.interaction.activatedLeaf == id)
    #expect(context.interaction.editingSessionGeneration == generation)
  }

  @Test func paintingShortenedEditorClampsOnlyTheVisualSnapshot() {
    let context = BlockContext()
    context.interaction.beginEditing(context.widgetID, caretOffset: 20)
    context.interaction.textSelectionRange = 10..<20
    context.interaction.editingText = "old long value"
    var changes = 0
    let editor = TextEditor(text: { "x" }, onChange: { _ in changes += 1 })
    var list = DrawList()
    editor.paint(into: &list, in: rect, context: context)
    #expect(context.interaction.caretOffset == 20)
    #expect(context.interaction.textSelectionRange == 10..<20)
    #expect(context.interaction.editingText == "old long value")
    #expect(changes == 0)
    #expect(
      list.commands.contains {
        if case .text(_, "x", _, _) = $0 { return true }
        return false
      })
  }

  private final class Capture {
    var phases: [InteractionPhase] = []
    var registrations = 0
    var paints = 0
  }

  private struct PhaseLeaf: PaintableBlock {
    let phase: InteractionPhase
    let capture: Capture
    var focusRule: FocusRule { .decorative }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func register(in rect: Rect, context: BlockContext) { capture.registrations += 1 }
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      capture.paints += 1
      list.text("\(phase)", at: rect.origin, color: .white)
    }

  }

  @Test func interactivePaintUsesTheRegisteredPhaseWithoutResolvingOrRegisteringAgain() {
    let capture = Capture()
    let context = BlockContext()
    let id = WidgetID("interactive")
    let interactive = Interactive(
      id: id, action: {},
      content: { phase in
        capture.phases.append(phase)
        return PhaseLeaf(phase: phase, capture: capture)
      })
    context.interaction.hoveredLeafID = id
    let resolved = BlockEngine.resolve(interactive, context: context)
    _ = resolved.sizeThatFits(rect.size)
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    resolved.register(in: rect)
    let phases = capture.phases
    let registrations = capture.registrations
    let leaves = context.interaction.builderRoot?.children.count
    var list = DrawList()
    resolved.paint(into: &list, in: rect)
    resolved.paint(into: &list, in: rect)
    #expect(capture.phases == phases)
    #expect(capture.registrations == registrations)
    #expect(context.interaction.builderRoot?.children.count == leaves)
    #expect(capture.paints == 2)
    #expect(
      list.commands.allSatisfy {
        if case .text(_, "hovered", _, _) = $0 { return true }
        return false
      })
    context.interaction.endFrame()
  }

  @Test func editorPaintDoesNotAdvanceDragViewportOrReplayEditing() {
    let context = BlockContext()
    let editor = TextEditor(text: { "ab\ncd\nef\ngh\nij" }, onChange: { _ in })
    func update(_ input: InputState) {
      context.interaction.beginFrame(input: input)
      BlockEngine.register(editor, in: rect, context: context)
      context.interaction.endFrame()
    }
    update(InputState())
    let origin = Point(x: 20, y: 10)
    update(InputState(pointerPosition: origin, pointerDown: true, pointerPressed: true))
    let below = Point(x: 20, y: 80)
    context.interaction.beginFrame(input: InputState(pointerPosition: below, pointerDown: true))
    let resolved = BlockEngine.resolve(editor, context: context)
    resolved.register(in: rect)
    let row = context.interaction.textDragViewportRow
    let caret = context.interaction.caretOffset
    let selection = context.interaction.textSelectionRange
    let leaves = context.interaction.builderRoot?.children.count
    #expect(row == 1)
    for _ in 0..<3 {
      var list = DrawList()
      resolved.paint(into: &list, in: rect)
      #expect(context.interaction.textDragViewportRow == row)
      #expect(context.interaction.caretOffset == caret)
      #expect(context.interaction.textSelectionRange == selection)
      #expect(context.interaction.builderRoot?.children.count == leaves)
    }
    context.interaction.endFrame()
  }

  @Test func shapingSnapshotValidityIncludesTextAndColumnsAndHasBoundedOwnership() {
    let preparation = TextLayoutPreparation()
    let original = preparation.resolve("ab\ncd", columns: 10)
    #expect(preparation.resolve("ab\ncd", columns: 10) === original)
    let changedText = preparation.resolve("ab\ncd\nef", columns: 10)
    #expect(changedText !== original)
    #expect(changedText.layout.lines.count == 3)
    let changedColumns = preparation.resolve("ab\ncd\nef", columns: 1)
    #expect(changedColumns !== changedText)
    #expect(changedColumns.layout.lines.count == 6)
    #expect(preparation.snapshot === changedColumns)
    // Only the latest value is cached, and a new update has its own preparation.
    #expect(preparation.resolve("ab\ncd", columns: 10) !== original)
    #expect(TextLayoutPreparation().resolve("ab\ncd", columns: 10) !== original)
  }

  @Test(arguments: [false, true])
  func updateAndPaintingShareTheMeasuredTextLayout(editor: Bool) {
    let context = BlockContext()
    let block: any Block =
      editor
      ? TextEditor(text: { "ab\ncd\nef" }, onChange: { _ in })
      : Text("ab\ncd\nef").wrapping().selectable()
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let resolved = BlockEngine.resolve(block, context: context)
    _ = resolved.sizeThatFits(rect.size)
    #expect(PipelineMetrics.snapshot.textLayouts == 1)
    context.interaction.beginFrame(input: InputState())
    resolved.register(in: rect)
    var list = DrawList()
    resolved.paint(into: &list, in: rect)
    resolved.paint(into: &list, in: rect)
    #expect(PipelineMetrics.snapshot.textLayouts == 1)
    context.interaction.endFrame()
  }

  @Test func editorPaintUsesTheCommittedUpdateWithoutReevaluatingTheTextBinding() {
    let context = BlockContext()
    var reads = 0
    var text = "before"
    let editor = TextEditor(
      text: {
        reads += 1
        return text
      }, onChange: { text = $0 })
    let resolved = BlockEngine.resolve(editor, context: context)
    context.interaction.beginFrame(input: InputState())
    resolved.register(in: rect)
    let registeredReads = reads
    text = "after"
    var first = DrawList()
    resolved.paint(into: &first, in: rect)
    #expect(reads == registeredReads)
    #expect(
      first.commands.contains {
        if case .text(_, "before", _, _) = $0 { return true }
        return false
      })
    context.interaction.endFrame()
    context.interaction.beginFrame(input: InputState())
    let updated = BlockEngine.resolve(editor, context: context)
    updated.register(in: rect)
    var second = DrawList()
    updated.paint(into: &second, in: rect)
    #expect(
      second.commands.contains {
        if case .text(_, "after", _, _) = $0 { return true }
        return false
      })
    context.interaction.endFrame()
  }

  @Test func editorHandlersDoNotRetainTheirInteractionOwner() {
    weak var interaction: Interaction?
    do {
      let context = BlockContext()
      interaction = context.interaction
      context.interaction.beginFrame(input: InputState())
      BlockEngine.register(TextEditor(text: { "text" }, onChange: { _ in }), in: rect, context: context)
      context.interaction.endFrame()
      #expect(interaction != nil)
    }
    #expect(interaction == nil)
  }

  @Test(arguments: [false, true])
  func opaqueTextHoverPreservesCommandOrder(selectable: Bool) {
    let text = selectable ? Text("visible glyphs").selectable() : Text("visible glyphs")
    var context = BlockContext()
    context.hoverStyle = .tint(.black)
    context.interaction.hoveredLeafID = context.widgetID
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    let resolved = text.prepareLayout(context: context)
    var list = DrawList()
    resolved.register(in: rect)
    resolved.paint(into: &list, in: rect)
    context.interaction.endFrame()
    let highlight = DrawCommand.fillRect(rect: rect, color: .black)
    if selectable {
      // The opaque hover background must be below selectable glyphs and selection.
      #expect(list.commands.first == highlight)
    } else {
      #expect(list.commands.last == highlight)
    }
  }
}
