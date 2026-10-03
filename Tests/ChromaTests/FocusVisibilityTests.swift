import Testing

@testable import Chroma

@MainActor
struct FocusVisibilityTests {
  private let viewport = Size(width: 200, height: 200)
  private let context = BlockContext()

  private func render(_ content: any Block, input: InputState = InputState()) {
    let isInitialFrame = context.interaction.tree == nil
    context.interaction.beginFrame(input: input)
    var drawList = DrawList()
    do {
      let resolved = BlockEngine.prepare(content, context: context)
      resolved.register(in: Rect(origin: .zero, size: viewport))
      resolved.paint(into: &drawList, in: Rect(origin: .zero, size: viewport))
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
    let content = ClippedColumn()

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
    let content = ScrollView {
      VStack(spacing: 0) {
        Button("Row 1") {}.sizing(y: .fixed(60))
        Button("Row 2") {}.sizing(y: .fixed(60))
        Button("Row 3") {}.sizing(y: .fixed(60))
        Button("Row 4") {}.sizing(y: .fixed(60))
      }
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
    let content = VStack {
      TextEditor(singleLine: true, text: { text }, onChange: { text = $0 })
        .onCommand(.action(.cancel)) {
          cancelCalls += 1
          return .handled
        }
      Button("Other") {}
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

private struct ClippedColumn: LayoutPreparingBlock {

  var focusRule: FocusRule { .container }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
  @MainActor func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let child = BlockEngine.prepare(
      VStack(spacing: 0) {
        Button("Row 1") {}
        Button("Row 2") {}
        Button("Row 3") {}
        Button("Row 4") {}
      }, context: context)
    return BlockEngine.Resolved(
      measure: { $0 },
      register: { rect in
        context.withInteractionClip(Rect(x: rect.minX, y: rect.minY, width: rect.size.width, height: 60)) {
          child.register(in: Rect(x: rect.minX, y: rect.minY, width: rect.size.width, height: 120))
        }
      },
      paint: { list, rect in
        child.paint(into: &list, in: Rect(x: rect.minX, y: rect.minY, width: rect.size.width, height: 120))
      })
  }
}
