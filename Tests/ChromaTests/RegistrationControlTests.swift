import Testing

@testable import Chroma

@MainActor
struct RegistrationControlTests {
  private let rect = Rect(x: 0, y: 0, width: 200, height: 80)

  private final class PhaseCapture {
    var registered: [InteractionPhase] = []
    var paints = 0
  }

  private struct PhaseProbe: Block {

    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        expandsHorizontally: false, expandsVertically: false,
        measure: { sizeThatFits($0, context: context) },
        register: { register(in: $0, context: context) },
        paint: { paint(into: &$0, in: $1, context: context) })
    }

    let phase: InteractionPhase
    let capture: PhaseCapture

    var focusRule: FocusRule { .standard }

    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }

    @MainActor func register(in rect: Rect, context: BlockContext) {
      capture.registered.append(phase)
    }

    @MainActor func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      capture.paints += 1
      list.fillRect(rect, color: .white)
    }
  }

  @Test func builtInControlsRegisterWithoutPainting() {
    let blocks: [any Block] = [
      Button("Action", action: {}),
      TextEditor(text: { "first\nsecond" }, onChange: { _ in }),
      TextEditor(singleLine: true, text: { "draft" }, onChange: { _ in }),
      Interactive(action: {}, content: { _ in Text("Content") }),
    ]
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    for block in blocks {
      PipelineMetrics.reset()
      let context = BlockContext()
      FrameProducer().refreshRegistrations(
        { buffer, context in buffer.emit(block, context: context) }, viewport: rect.size, context: context)
      let metrics = PipelineMetrics.snapshot
      #expect(metrics.registrations > 0)
      #expect(metrics.paints == 0)
      #expect(metrics.drawingCommands == 0)
      #expect(context.interaction.tree?.children.count == 1)
      #expect(context.interaction.tree?.children.first?.rect == rect)
    }
  }

  @Test func interactiveRegistrationUsesCurrentPhaseAndClaimsChildFocus() {
    let capture = PhaseCapture()
    let context = BlockContext()
    let block = Interactive(action: {}, content: { phase in PhaseProbe(phase: phase, capture: capture) })
    @MainActor func register(_ input: InputState) {
      beginTestFrame(context.interaction, input: input)
      var buffer = LayoutBuffer()
      let node = buffer.emit(block, context: context)
      buffer.register(node, in: rect)
      context.interaction.endFrame()
      #expect(context.interaction.tree?.children.count == 1)
    }
    register(InputState(pointerPosition: Point(x: -10, y: -10)))
    let point = Point(x: 10, y: 10)
    register(InputState(pointerPosition: point))
    register(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    #expect(capture.registered == [.idle, .hovered, .pressed])
    #expect(capture.paints == 0)
  }

  @Test func buttonReleaseUsesFreshRegisteredActionWithoutPresentation() {
    let context = BlockContext()
    let producer = FrameProducer()
    var actions: [String] = []
    func refresh(_ label: String) {
      producer.refreshRegistrations(
        { buffer, context in
          buffer.emit(Button(label, id: WidgetID("action"), action: { actions.append(label) }), context: context)
        },
        viewport: rect.size, context: context)
    }
    refresh("before")
    let point = Point(x: 10, y: 10)
    context.interaction.processInput(
      InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    refresh("after")
    context.interaction.processInput(InputState(pointerPosition: point, pointerReleased: true))
    context.interaction.finishInput()
    #expect(actions == ["after"])
    refresh("after")
    #expect(actions == ["after"])
  }

  @Test func textRegistrationRefreshesVerticalLayoutBeforeNextEditingEvent() throws {
    let context = BlockContext()
    let producer = FrameProducer()
    var text = "a"
    let editor = TextEditor(text: { text }, onChange: { text = $0 })
    func refresh() {
      producer.refreshRegistrations(
        { buffer, context in buffer.emit(editor, context: context) }, viewport: rect.size, context: context)
    }
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    refresh()
    let id = try #require(context.interaction.tree?.children.first?.leafID)
    context.focus(id, editing: true)
    refresh()
    context.interaction.processInput(InputState(textEvents: [.insert("\nb")]))
    refresh()
    context.interaction.processInput(InputState(textEvents: [.moveCaretUp]))
    #expect(text == "a\nb")
    #expect(context.interaction.caretOffset == 1)
    #expect(PipelineMetrics.snapshot.paints == 0)
    #expect(PipelineMetrics.snapshot.drawingCommands == 0)
  }

  @Test(arguments: [false, true])
  func textRegistrationKeepsSubmitBehavior(singleLine: Bool) throws {
    let context = BlockContext()
    let producer = FrameProducer()
    var text = "draft"
    let editor = TextEditor(singleLine: singleLine, text: { text }, onChange: { text = $0 })
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(editor, context: context) }, viewport: rect.size, context: context)
    let id = try #require(context.interaction.tree?.children.first?.leafID)
    context.focus(id, editing: true)
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(editor, context: context) }, viewport: rect.size, context: context)
    context.interaction.processInput(InputState(textEvents: [.submit]))
    #expect(text == (singleLine ? "draft" : "draft\n"))
    #expect(context.interaction.isTextEditing == !singleLine)
  }

  @Test func registrationAndPaintingUseSameDragViewportAndPointerOffsets() {
    let registration = BlockContext()
    let presentation = BlockContext()
    let editor = TextEditor(text: { "ab\ncd\nef\ngh\nij" }, onChange: { _ in })
    func frame(_ input: InputState) {
      beginTestFrame(registration.interaction, input: input)
      var direct = LayoutBuffer()
      let node = direct.textEditor(editor, context: registration)
      direct.register(node, in: rect)
      registration.interaction.endFrame()
      beginTestFrame(presentation.interaction, input: input)
      var list = DrawList()
      var resolvedBuffer = LayoutBuffer()
      let resolved = resolvedBuffer.emit(editor, context: presentation)
      resolvedBuffer.register(resolved, in: rect)
      resolvedBuffer.paint(resolved, into: &list, in: rect)
      presentation.interaction.endFrame()
      #expect(registration.interaction.caretOffset == presentation.interaction.caretOffset)
      #expect(registration.interaction.textSelectionRange == presentation.interaction.textSelectionRange)
      #expect(registration.interaction.textDragViewportRow == presentation.interaction.textDragViewportRow)
    }
    frame(InputState())
    let origin = Point(x: 20, y: 10)
    frame(InputState(pointerPosition: origin, pointerDown: true, pointerPressed: true))
    #expect(registration.interaction.caretOffset == 1)
    let below = Point(x: 20, y: 80)
    frame(InputState(pointerPosition: below, pointerDown: true))
    #expect(registration.interaction.textDragViewportRow == 1)
    #expect(registration.interaction.textSelectionRange == 1..<7)
    frame(InputState(pointerPosition: below, pointerDown: true))
    #expect(registration.interaction.textDragViewportRow == 2)
    #expect(registration.interaction.textSelectionRange == 1..<10)
    frame(InputState(pointerPosition: below, pointerReleased: true))
    #expect(registration.interaction.textDragViewportRow == nil)
    #expect(registration.interaction.textSelectionRange == 1..<13)
  }

  @Test func refreshingActiveTextDragDoesNotAdvanceViewportOrReplaySelection() {
    let context = BlockContext()
    let editor = TextEditor(text: { "ab\ncd\nef\ngh\nij" }, onChange: { _ in })
    func frame(_ input: InputState) {
      beginTestFrame(context.interaction, input: input)
      var buffer = LayoutBuffer()
      let node = buffer.emit(editor, context: context)
      buffer.register(node, in: rect)
      context.interaction.endFrame()
    }
    frame(InputState())
    let origin = Point(x: 20, y: 10)
    frame(InputState(pointerPosition: origin, pointerDown: true, pointerPressed: true))
    let below = Point(x: 20, y: 80)
    frame(InputState(pointerPosition: below, pointerDown: true))
    #expect(context.interaction.textDragViewportRow == 1)
    #expect(context.interaction.textSelectionRange == 1..<7)

    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let producer = FrameProducer()
    for _ in 0..<2 {
      producer.refreshRegistrations(
        { buffer, context in buffer.emit(editor, context: context) }, viewport: rect.size, context: context)
      #expect(context.interaction.textDragViewportRow == 1)
      #expect(context.interaction.textSelectionRange == 1..<7)
      #expect(context.interaction.caretOffset == 7)
      #expect(context.interaction.dragOrigin == origin)
      #expect(context.interaction.dragCurrent == below)
    }
    context.interaction.processInput(InputState(pointerPosition: below, pointerDown: true))
    #expect(context.interaction.textSelectionRange == 1..<10)
    #expect(context.interaction.caretOffset == 10)
    #expect(PipelineMetrics.snapshot.paints == 0)
    #expect(PipelineMetrics.snapshot.drawingCommands == 0)
  }
}
