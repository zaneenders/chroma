import Testing

@testable import Chroma

@MainActor
struct PointerScrollFocusTests {
  @Test func recoveringFocusAfterVirtualScrollDoesNotMoveTheNextClickTarget() {
    let runtime = WindowRuntime()
    let controller = ScrollViewController()
    var clicks: [Int] = []
    let content: LayoutBuilder = { buffer, context in
      let node317 = buffer.scrollView(
        ScrollView(
          data: 0..<30, rowHeight: 30, controller: controller,
          build: { buffer, context, index in
            let node316 = buffer.interactive(
              action: { clicks.append(index) },
              content: { buffer, context, _ in
                return buffer.text(Text("Row \(index)"), context: context)
              }, context: context)
            return node316
          }), context: context)
      return node317
    }
    runtime.build = content
    func render(_ input: InputState = InputState()) {
      _ = runtime.render(
        viewport: Size(width: 200, height: 100),
        input: input,
        onChange: {})
    }
    render()
    let first = Point(x: 10, y: 10)
    render(InputState(pointerPosition: first, pointerPressed: true))
    render(InputState(pointerPosition: first, pointerReleased: true))
    #expect(clicks == [0])

    controller.scrollToBottom()
    render()
    #expect(controller.offset == 800)
    let last = Point(x: 10, y: 80)
    render(InputState(pointerPosition: last, pointerPressed: true))
    #expect(controller.offset == 800)
    render(InputState(pointerPosition: last, pointerReleased: true))
    #expect(clicks == [0, 29])
  }

  @Test(arguments: [false, true])
  func pressingOversizedRowPreservesScrollOffset(hasControl: Bool) {
    let runtime = WindowRuntime()
    let context = runtime.context
    let controller = ScrollViewController()
    let target = FocusTarget()
    let row: LayoutBuilder = { buffer, context in
      if hasControl {
        return buffer.focus(target, context: context) { buffer, context in
          let button = buffer.button(Button("Message") {}, context: context)
          return buffer.sizing(button, y: .fixed(2000), context: context)
        }
      }
      let text = buffer.text(Text("Message"), context: context)
      return buffer.sizing(text, y: .fixed(2000), context: context)
    }
    let content: LayoutBuilder = { buffer, context in
      let node318 = buffer.scrollView(
        ScrollView(
          "Transcript", controller: controller,
          rows: [ScrollView.Row(id: "message", build: row)]), context: context)
      return node318
    }
    runtime.build = content
    func render(_ input: InputState = InputState()) {
      _ = runtime.render(
        viewport: Size(width: 400, height: 200),
        input: input, onChange: {})
    }
    render()
    controller.scroll(to: 500)
    render()
    let offset = controller.offset
    let point = Point(x: 100, y: 100)
    render(
      InputState(
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
    let runtime = WindowRuntime()
    let controller = ScrollViewController()
    let selection = ScrollSelection<Int>()
    let targets = [FocusTarget(), FocusTarget()]
    let content: LayoutBuilder = { buffer, context in
      let node321 = buffer.scrollView(
        ScrollView(
          data: [Item(id: 0), Item(id: 1)], rowHeight: 1000, controller: controller, selection: selection,
          build: { buffer, context, item in
            let node320 = buffer.focus(
              targets[item.id], context: context,
              content: { buffer, context in
                return buffer.button(Button("Message \(item.id)") {}, context: context)
              })
            return node320
          }), context: context)
      return node321
    }
    runtime.build = content
    func render(_ input: InputState = InputState()) {
      _ = runtime.render(
        viewport: Size(width: 400, height: 200),
        input: input, onChange: {})
    }
    render()
    controller.scroll(to: 500)
    render()
    let point = Point(x: 100, y: 100)
    render(
      InputState(
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
