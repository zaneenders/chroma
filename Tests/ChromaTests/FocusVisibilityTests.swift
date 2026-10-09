import Testing

@testable import Chroma

@MainActor
struct FocusVisibilityTests {
  private let viewport = Size(width: 200, height: 200)
  private let context = LayoutContext()

  private func render(_ content: @escaping LayoutBuilder, input: InputState = InputState()) {
    let isInitialFrame = context.interaction.tree == nil
    beginTestFrame(context.interaction, input: input)
    var drawList = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = content(&resolvedBuffer, context)
      resolvedBuffer.register(resolved, in: Rect(origin: .zero, size: viewport))
      resolvedBuffer.paint(resolved, into: &drawList, in: Rect(origin: .zero, size: viewport))
    }
    context.interaction.endFrame()
    if isInitialFrame, context.interaction.selection == nil { context.interaction.focusFirstControlForTest() }
  }

  private var selectedIsVisible: Bool {
    let interaction = context.interaction
    guard let tree = interaction.tree, let selection = interaction.selection else { return false }
    return tree.node(at: selection)?.hitRect != .zero
  }

  @Test func clippedControlsCannotTakeFocus() {
    let interaction = context.interaction
    let content: LayoutBuilder = { buffer, context in
      return ClippedColumn().build(into: &buffer, context: context)
    }

    render(content)
    let first = interaction.selectedLeafID
    #expect(first != nil)
    #expect(selectedIsVisible)

    render(content, input: InputState(commands: [.navigation(.down)]))
    let second = interaction.selectedLeafID
    #expect(second != first)
    #expect(selectedIsVisible)

    render(content, input: InputState(commands: [.navigation(.down)]))
    #expect(interaction.selectedLeafID == second)
    #expect(selectedIsVisible)

    render(content, input: InputState(commands: [.navigation(.up)]))
    #expect(interaction.selectedLeafID == first)
  }

  @Test func revealableControlsRemainReachable() {
    let interaction = context.interaction
    let content: LayoutBuilder = { buffer, context in
      let node164 = buffer.scrollView(
        ScrollView(build: { buffer, context in
          let node155 = buffer.button(Button("Row 1") {}, context: context.childScope(0))
          let node156 = buffer.sizing(node155, y: .fixed(60), context: context.childScope(0))
          let node157 = buffer.button(Button("Row 2") {}, context: context.childScope(1))
          let node158 = buffer.sizing(node157, y: .fixed(60), context: context.childScope(1))
          let node159 = buffer.button(Button("Row 3") {}, context: context.childScope(2))
          let node160 = buffer.sizing(node159, y: .fixed(60), context: context.childScope(2))
          let node161 = buffer.button(Button("Row 4") {}, context: context.childScope(3))
          let node162 = buffer.sizing(node161, y: .fixed(60), context: context.childScope(3))
          let node163 = buffer.stack(
            [node156, node158, node160, node162], axis: .vertical, spacing: 0, context: context)
          return node163
        }), context: context)
      return node164
    }
    render(content)
    render(content, input: InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
    let first = interaction.selectedLeafID

    for _ in 0..<3 {
      render(content, input: InputState(commands: [.navigation(.down)]))
      #expect(selectedIsVisible)
    }
    #expect(interaction.selectedLeafID != first)
  }

  @Test func escapeLeavesTextInputBeforeCancelHandlers() {
    let interaction = context.interaction
    var text = ""
    var cancelCalls = 0
    let content: LayoutBuilder = { buffer, context in
      let node165 = buffer.textEditor(
        TextEditor(singleLine: true, text: { text }, onChange: { text = $0 }), context: context.childScope(0))
      let node166 = buffer.onCommand(
        node165, .action(.cancel), context: context.childScope(0),
        action: {
          cancelCalls += 1
          return .handled
        })
      let node167 = buffer.button(Button("Other") {}, context: context.childScope(1))
      return buffer.stack([node166, node167], axis: .vertical, context: context)
    }

    render(content)
    render(content, input: InputState(commands: [.action(.activate)]))
    #expect(interaction.mode == .editing)

    render(content, input: InputState(commands: [.action(.cancel)]))
    #expect(interaction.mode == .movement)
    #expect(interaction.editingLeaf != nil)
    #expect(cancelCalls == 0)
  }
}

private struct ClippedColumn {

  @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let context = context.component(Self.self)
    var children: [LayoutNode] = []
    for index in 1...4 {
      children.append(buffer.button(Button("Row \(index)") {}, context: context.childScope(0).childScope(index - 1)))
    }
    let stack = buffer.stack(children, axis: .vertical, spacing: 0, context: context.childScope(0))
    let padded = buffer.padding(stack, EdgeInsets(bottom: -60), context: context.childScope(0))
    let sized = buffer.sizing(padded, y: .fixed(60), context: context.childScope(0))
    let clipped = buffer.clip(sized, context: context.childScope(0))
    return buffer.overlay([clipped], context: context)
  }
}
