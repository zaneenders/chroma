import Testing

@testable import Chroma

@MainActor
struct TypedControlLoweringTests {
  private let rect = Rect(x: 0, y: 0, width: 200, height: 80)

  @Test func idleMeasurementAndRegistrationShareOneChild() {
    let context = BlockContext()
    var phases: [InteractionPhase] = []
    var buffer = LayoutBuffer()
    let node = buffer.emit(
      Interactive(action: {}) { phase in
        phases.append(phase)
        return Text("same child")
      }, context: context)
    _ = buffer.expandsHorizontally(node)
    _ = buffer.expandsVertically(node)
    _ = buffer.sizeThatFits(node, rect.size)
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    buffer.register(node, in: rect)
    var list = DrawList()
    buffer.paint(node, into: &list, in: rect)
    buffer.paint(node, into: &list, in: rect)
    #expect(phases == [.idle])
    #expect(buffer.count == 2)
    #expect(context.interaction.builderRoot?.children.count == 1)
    context.interaction.endFrame()
  }

  @Test func eachPhaseIsLoweredOnceWithinTheOperation() {
    let context = BlockContext()
    var phases: [InteractionPhase] = []
    var buffer = LayoutBuffer()
    var node = InteractiveNode(
      id: nil, action: {},
      content: { phase in
        phases.append(phase)
        return Text("\(phase)")
      }, context: context)
    let idle = node.child(for: .idle, in: &buffer)
    let hovered = node.child(for: .hovered, in: &buffer)
    let pressed = node.child(for: .pressed, in: &buffer)
    let idleAgain = node.child(for: .idle, in: &buffer)
    let pressedAgain = node.child(for: .pressed, in: &buffer)
    let hoveredAgain = node.child(for: .hovered, in: &buffer)
    #expect(idleAgain == idle)
    #expect(pressedAgain == pressed)
    #expect(hoveredAgain == hovered)
    #expect(phases == [.idle, .hovered, .pressed])
    #expect(buffer.count == 3)
  }

  @Test func paintKeepsRegisteredPhaseAndDoesNotResolveOrRegisterAgain() {
    let context = BlockContext()
    let id = WidgetID("phase")
    var phases: [InteractionPhase] = []
    var buffer = LayoutBuffer()
    let node = buffer.emit(
      Interactive(id: id, action: {}) { phase in
        phases.append(phase)
        return Text("\(phase)")
      }, context: context)
    _ = buffer.sizeThatFits(node, rect.size)
    context.interaction.hoveredLeafID = id
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    buffer.register(node, in: rect)
    let registeredCount = context.interaction.builderRoot?.children.count
    let nodeCount = buffer.count
    context.interaction.hoveredLeafID = nil
    var list = DrawList()
    buffer.paint(node, into: &list, in: rect)
    buffer.paint(node, into: &list, in: rect)
    #expect(phases == [.idle, .hovered])
    #expect(buffer.count == nodeCount)
    #expect(context.interaction.builderRoot?.children.count == registeredCount)
    #expect(
      list.paintSnapshot.allSatisfy {
        if case .text(_, "hovered", _, _) = $0 { return true }
        return false
      })
    context.interaction.endFrame()
  }

  @Test func editorReadsBindingOnceAcrossLayoutRegistrationAndDrawing() throws {
    let context = BlockContext()
    var reads = 0
    var text = "a👨‍👩‍👧‍👦e\u{301}"
    let snapshot = text
    let editor = TextEditor(
      text: {
        reads += 1
        return text
      }, onChange: { text = $0 })
    var buffer = LayoutBuffer()
    let node = buffer.emit(editor, context: context)
    #expect(reads == 1)
    text = "later binding value"
    _ = buffer.sizeThatFits(node, rect.size)
    _ = buffer.sizeThatFits(node, Size(width: 100, height: 80))
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    buffer.register(node, in: rect)
    context.interaction.endFrame()
    let id = try #require(context.interaction.tree?.children.first?.leafID)
    context.focus(id, editing: true)
    context.interaction.caretOffset = 99
    context.interaction.textSelectionRange = 1..<99
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    buffer.register(node, in: rect)
    var list = DrawList()
    buffer.paint(node, into: &list, in: rect)
    buffer.paint(node, into: &list, in: rect)
    #expect(reads == 1)
    #expect(context.interaction.editingText == snapshot)
    #expect(context.interaction.caretOffset == 3)
    #expect(context.interaction.textSelectionRange == 1..<3)
    #expect(
      list.paintSnapshot.contains {
        if case .text(_, let value, _, _) = $0 { return value == snapshot }
        return false
      })
    context.interaction.endFrame()
    buffer.reset()
    let fresh = buffer.emit(editor, context: context)
    #expect(reads == 2)
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    buffer.register(fresh, in: rect)
    #expect(context.interaction.editingText == text)
    context.interaction.endFrame()
  }

  @Test func resetReplacesControlCallbacksBeforeAnotherInputEvent() {
    let context = BlockContext()
    var actions: [String] = []
    var buffer = LayoutBuffer()
    func action(_ value: String) -> Button {
      Button(value, id: WidgetID("action"), action: { actions.append(value) })
    }
    let first = buffer.emit(action("first"), context: context)
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    buffer.register(first, in: rect)
    context.interaction.endFrame()
    let point = Point(x: 10, y: 10)
    context.interaction.processInput(
      InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    buffer.reset()
    let second = buffer.emit(action("second"), context: context)
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    buffer.register(second, in: rect)
    context.interaction.endFrame()
    context.interaction.processInput(InputState(pointerPosition: point, pointerReleased: true))
    context.interaction.finishInput()
    #expect(actions == ["second"])
  }
}
