import Testing

@testable import Chroma

@MainActor
struct ControlPaintIsolationTests {
  private let rect = Rect(x: 0, y: 0, width: 200, height: 80)

  @Test func emittingAndMeasuringControlsDoesNotCreateInteractionState() {
    var actions = 0
    var changes = 0
    let controls: [LayoutBuilder] = [
      { buffer, context in buffer.button(Button("Action", action: { actions += 1 }), context: context) },
      { buffer, context in
        buffer.interactive(
          action: { actions += 1 },
          content: { buffer, context, phase in buffer.text(Text("\(phase)"), context: context) }, context: context)
      },
      { buffer, context in
        buffer.textEditor(TextEditor(text: { "draft" }, onChange: { _ in changes += 1 }), context: context)
      },
      { buffer, context in buffer.text(Text("selectable").selectable(), context: context) },
    ]
    for control in controls {
      let context = LayoutContext()
      var buffer = LayoutBuffer()
      let resolved = control(&buffer, context)
      _ = buffer.sizeThatFits(resolved, rect.size)
      _ = buffer.expandsHorizontally(resolved)
      _ = buffer.expandsVertically(resolved)
      #expect(context.interaction.tree == nil)
      #expect(context.interaction.builderRoot == nil)
      #expect(context.interaction.building.inputHandlers.isEmpty)
      #expect(context.interaction.building.buttonActions.isEmpty)
      #expect(context.interaction.building.focusTargets.isEmpty)
      #expect(context.interaction.building.readOnlyTexts.isEmpty)
      #expect(context.interaction.editingLeaf == nil)
    }
    #expect(actions == 0)
    #expect(changes == 0)
  }

  @Test func visualStateDoesNotExposeActivationEdgesOrConsumePendingFocus() {
    let context = LayoutContext()
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

  @Test func paintingShortenedEditorClampsOnlyTheVisualSnapshot() throws {
    let context = LayoutContext()
    var changes = 0
    let editor = TextEditor(text: { "x" }, onChange: { _ in changes += 1 })
    var list = DrawList()
    var buffer = LayoutBuffer()
    let node = buffer.textEditor(editor, context: context)
    beginTestFrame(context.interaction, input: InputState())
    buffer.register(node, in: rect)
    context.interaction.endFrame()
    let id = try #require(context.interaction.tree?.children.first?.leafID)
    context.interaction.beginEditing(id, caretOffset: 20)
    context.interaction.textSelectionRange = 10..<20
    context.interaction.editingText = "old long value"
    buffer.paint(node, into: &list, in: rect)
    #expect(context.interaction.caretOffset == 20)
    #expect(context.interaction.textSelectionRange == 10..<20)
    #expect(context.interaction.editingText == "old long value")
    #expect(changes == 0)
    #expect(
      list.paintSnapshot.contains {
        if case .text(_, "x", _, _) = $0 { return true }
        return false
      })
  }

  private final class Capture {
    var phases: [InteractionPhase] = []
    var registrations = 0
    var paints = 0
  }

  @Test func interactivePaintUsesTheRegisteredPhaseWithoutResolvingOrRegisteringAgain() {
    let capture = Capture()
    let context = LayoutContext()
    let id = WidgetID("interactive")
    context.interaction.hoveredLeafID = id
    var buffer = LayoutBuffer()
    let resolved = buffer.interactive(
      id: id, action: {},
      content: { buffer, context, phase in
        capture.phases.append(phase)
        return buffer.customLeaf(
          context: context, focusRule: .decorative, measure: { $0 },
          register: { _ in capture.registrations += 1 },
          paint: { list, rect in
            capture.paints += 1
            list.text("\(phase)", at: rect.origin, color: .white)
          })
      }, context: context)
    _ = buffer.sizeThatFits(resolved, rect.size)
    context.interaction.beginFrame(input: InputState())
    buffer.register(resolved, in: rect)
    let phases = capture.phases
    let registrations = capture.registrations
    let leaves = context.interaction.builderRoot?.children.count
    var list = DrawList()
    buffer.paint(resolved, into: &list, in: rect)
    buffer.paint(resolved, into: &list, in: rect)
    #expect(capture.phases == phases)
    #expect(capture.registrations == registrations)
    #expect(context.interaction.builderRoot?.children.count == leaves)
    #expect(capture.paints == 2)
    #expect(
      list.paintSnapshot.allSatisfy {
        if case .text(_, "hovered", _, _) = $0 { return true }
        return false
      })
    context.interaction.endFrame()
  }

  @Test func editorPaintDoesNotAdvanceDragViewportOrReplayEditing() {
    let context = LayoutContext()
    let editor = TextEditor(text: { "ab\ncd\nef\ngh\nij" }, onChange: { _ in })
    func update(_ input: InputState) {
      beginTestFrame(context.interaction, input: input)
      var buffer = LayoutBuffer()
      let node = buffer.textEditor(editor, context: context)
      buffer.register(node, in: rect)
      context.interaction.endFrame()
    }
    update(InputState())
    let origin = Point(x: 20, y: 10)
    update(InputState(pointerPosition: origin, pointerDown: true, pointerPressed: true))
    let below = Point(x: 20, y: 80)
    beginTestFrame(context.interaction, input: InputState(pointerPosition: below, pointerDown: true))
    var buffer = LayoutBuffer()
    let resolved = buffer.textEditor(editor, context: context)
    buffer.register(resolved, in: rect)
    let row = context.interaction.textDragViewportRow
    let caret = context.interaction.caretOffset
    let selection = context.interaction.textSelectionRange
    let leaves = context.interaction.builderRoot?.children.count
    #expect(row == 1)
    for _ in 0..<3 {
      var list = DrawList()
      buffer.paint(resolved, into: &list, in: rect)
      #expect(context.interaction.textDragViewportRow == row)
      #expect(context.interaction.caretOffset == caret)
      #expect(context.interaction.textSelectionRange == selection)
      #expect(context.interaction.builderRoot?.children.count == leaves)
    }
    context.interaction.endFrame()
  }

  @Test(arguments: [false, true])
  func updateAndPaintingShareTheMeasuredTextLayout(editor: Bool) {
    let context = LayoutContext()
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    var buffer = LayoutBuffer()
    let resolved =
      editor
      ? buffer.textEditor(TextEditor(text: { "ab\ncd\nef" }, onChange: { _ in }), context: context)
      : buffer.text(Text("ab\ncd\nef").wrapping().selectable(), context: context)
    _ = buffer.sizeThatFits(resolved, rect.size)
    #expect(PipelineMetrics.snapshot.textLayouts == 1)
    beginTestFrame(context.interaction, input: InputState())
    buffer.register(resolved, in: rect)
    var list = DrawList()
    buffer.paint(resolved, into: &list, in: rect)
    buffer.paint(resolved, into: &list, in: rect)
    #expect(PipelineMetrics.snapshot.textLayouts == 1)
    context.interaction.endFrame()
  }

  @Test func editorPaintUsesTheCommittedUpdateWithoutReevaluatingTheTextBinding() {
    let context = LayoutContext()
    var reads = 0
    var text = "before"
    let editor = TextEditor(
      text: {
        reads += 1
        return text
      }, onChange: { text = $0 })
    var buffer = LayoutBuffer()
    let resolved = buffer.textEditor(editor, context: context)
    beginTestFrame(context.interaction, input: InputState())
    buffer.register(resolved, in: rect)
    let registeredReads = reads
    text = "after"
    var first = DrawList()
    buffer.paint(resolved, into: &first, in: rect)
    #expect(reads == registeredReads)
    #expect(
      first.paintSnapshot.contains {
        if case .text(_, "before", _, _) = $0 { return true }
        return false
      })
    context.interaction.endFrame()
    beginTestFrame(context.interaction, input: InputState())
    buffer.reset()
    let updated = buffer.textEditor(editor, context: context)
    buffer.register(updated, in: rect)
    var second = DrawList()
    buffer.paint(updated, into: &second, in: rect)
    #expect(
      second.paintSnapshot.contains {
        if case .text(_, "after", _, _) = $0 { return true }
        return false
      })
    context.interaction.endFrame()
  }

  @Test func editorHandlersDoNotRetainTheirInteractionOwner() {
    weak var interaction: Interaction?
    do {
      let context = LayoutContext()
      interaction = context.interaction
      beginTestFrame(context.interaction, input: InputState())
      var buffer = LayoutBuffer()
      let node = buffer.textEditor(TextEditor(text: { "text" }, onChange: { _ in }), context: context)
      buffer.register(node, in: rect)
      context.interaction.endFrame()
      #expect(interaction != nil)
    }
    #expect(interaction == nil)
  }

  @Test(arguments: [false, true])
  func opaqueTextHoverPreservesCommandOrder(selectable: Bool) {
    let text = selectable ? Text("visible glyphs").selectable() : Text("visible glyphs")
    var context = LayoutContext()
    context.hoverStyle = .tint(.black)
    context.interaction.hoveredLeafID = context.scoped([.component(ObjectIdentifier(Text.self))]).widgetID
    context.interaction.beginFrame(input: InputState())
    var buffer = LayoutBuffer()
    let resolved = buffer.text(text, context: context)
    var list = DrawList()
    buffer.register(resolved, in: rect)
    buffer.paint(resolved, into: &list, in: rect)
    context.interaction.endFrame()
    let highlight = PaintSnapshotEntry.fillRect(rect: rect, color: .black)
    if selectable {
      // The opaque hover background must be below selectable glyphs and selection.
      #expect(list.paintSnapshot.first == highlight)
    } else {
      #expect(list.paintSnapshot.last == highlight)
    }
  }
}
