import Testing

@testable import Chroma

@MainActor
struct PointerScrollFocusTests {
  @Test(arguments: [false, true])
  func pressingOversizedRowPreservesScrollOffset(hasControl: Bool) {
    let context = BlockContext()
    let producer = FrameProducer()
    let controller = ScrollViewController()
    let target = FocusTarget()
    let row: any Block = hasControl
      ? Button("Message") {}.sizing(y: .fixed(2000)).focusTarget(target)
      : Text("Message").sizing(y: .fixed(2000))
    let content = ScrollView(
      "Transcript", controller: controller,
      rows: [ScrollView.Row(id: "message", content: row)])
    func render(_ input: InputState = InputState()) {
      _ = producer.render(
        content: content, viewport: Size(width: 400, height: 200),
        input: input, context: context, onChange: {})
    }
    render()
    controller.scroll(to: 500)
    render()
    let offset = controller.offset
    let point = Point(x: 100, y: 100)
    render(InputState(
      pointerPosition: point, pointerPressPosition: point,
      pointerDown: true, pointerPressed: true))
    #expect(controller.offset == offset)
    #expect(context.interaction.selectedLeafID != nil)
    if hasControl { #expect(target.isFocused) }
    render(InputState(pointerPosition: Point(x: 100, y: 150), pointerDown: true))
    #expect(controller.offset == offset)
    render(InputState(pointerPosition: Point(x: 100, y: 150), pointerReleased: true))
    #expect(controller.offset == offset)
    if hasControl {
      target.focus()
      render()
      render()
      #expect(target.isFocused)
      #expect(controller.offset != offset)
    }
  }

  @Test func pointerSelectionPreservesLogicalSelectionAndKeyboardReveal() {
    struct Item: Identifiable { let id: Int }
    let context = BlockContext()
    let producer = FrameProducer()
    let controller = ScrollViewController()
    let selection = ScrollSelection<Int>()
    let targets = [FocusTarget(), FocusTarget()]
    let content = ScrollView(
      data: [Item(id: 0), Item(id: 1)], rowHeight: 1000,
      controller: controller, selection: selection
    ) { item in
      Button("Message \(item.id)") {}.focusTarget(targets[item.id])
    }
    func render(_ input: InputState = InputState()) {
      _ = producer.render(
        content: content, viewport: Size(width: 400, height: 200),
        input: input, context: context, onChange: {})
    }
    render()
    controller.scroll(to: 500)
    render()
    let point = Point(x: 100, y: 100)
    render(InputState(
      pointerPosition: point, pointerPressPosition: point,
      pointerDown: true, pointerPressed: true))
    #expect(controller.offset == 500)
    #expect(selection.selectedID == 0)
    #expect(targets[0].isFocused)
    render(InputState(commands: [.navigation(.down)]))
    render()
    #expect(selection.selectedID == 1)
    #expect(targets[1].isFocused)
    #expect(controller.offset > 500)
  }
}
