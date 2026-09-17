import Testing

@testable import Chroma

@MainActor
struct StructuralInteractionTests {
  @MainActor private final class Harness {
    let context = RenderContext()
    let producer = FrameProducer()

    func render(_ content: any Block, input: InputState = InputState()) {
      _ = producer.render(
        content: content, viewport: Size(width: 200, height: 100),
        input: input, context: context, onChange: {})
    }

    var press: InputState {
      InputState(
        pointerPosition: Point(x: 5, y: 5), pointerPressPosition: Point(x: 5, y: 5),
        pointerDown: true, pointerPressed: true)
    }

    var release: InputState {
      InputState(pointerPosition: Point(x: 5, y: 5), pointerReleased: true)
    }
  }

  @Test(arguments: ["horizontal", "vertical", "overlay"])
  func rawTupleChildrenHaveIndependentActions(container: String) {
    let harness = Harness()
    var calls: [String] = []
    let children: [any Block] = [
      Button("A") { calls.append("A") },
      Button("B") { calls.append("B") },
    ]
    let content: any Block
    switch container {
    case "horizontal": content = HStack(content: { return TupleBlock(children: children) })
    case "vertical": content = VStack(content: { return TupleBlock(children: children) })
    default: content = ZStack(content: { return TupleBlock(children: children) })
    }
    harness.render(content)
    #expect(harness.context.interaction.buttonActions.count == 2)
    harness.render(content, input: InputState(commands: [.action(.activate)]))
    #expect(calls == ["A"])
  }

  @Test func collectionModifiersPreservePressAndSeparateBackgroundActions() {
    struct Item: Identifiable { let id: Int }
    let harness = Harness()
    var activations = 0
    let rows = ForEach([Item(id: 1), Item(id: 2)]) { _ in
      Button("Row") { activations += 1 }
    }
    harness.render(VStack { rows }, input: harness.press)
    let id = harness.context.interaction.pressedLeaf
    #expect(id != nil)
    let styled = VStack { rows.padding(0).background(Button("Background") {}) }
    harness.render(styled, input: harness.release)
    #expect(activations == 1)
    #expect(harness.context.interaction.selectedLeafID == id)
    #expect(harness.context.interaction.buttonActions.count == 4)
  }

  @Test func collectionModifiersPreserveEditingAcrossReordering() {
    struct Item: Identifiable { let id: Int }
    let harness = Harness()
    let target = FocusTarget()
    var text = ""
    func content(_ ids: [Int], styled: Bool) -> VStack {
      let rows = ForEach(ids.map { Item(id: $0) }) { item in
        if item.id == 1 {
          TextField(text: { text }, onChange: { text = $0 }).focusTarget(target)
        } else {
          Button("Other") {}
        }
      }
      let child: any Block = styled ? rows.padding(0).clipped() : rows
      return VStack { child }
    }
    target.focus(editing: true)
    harness.render(content([1, 2], styled: false))
    let id = harness.context.interaction.editingLeaf
    #expect(id != nil)
    harness.render(content([2, 1], styled: true), input: InputState(textEvents: [.insert("x")]))
    #expect(harness.context.interaction.editingLeaf == id)
    #expect(text == "x")
  }

  @Test func labelChangesPreserveFocusAndPress() {
    let harness = Harness()
    var activations = 0
    harness.render(Button("Before") { activations += 1 }, input: harness.press)
    let id = harness.context.interaction.pressedLeaf
    #expect(id != nil)
    harness.render(
      Button("After") { activations += 1 },
      input: InputState(pointerPosition: Point(x: 5, y: 5), pointerDown: true))
    #expect(harness.context.interaction.pressedLeaf == id)
    #expect(harness.context.interaction.selectedLeafID == id)
    harness.render(Button("After") { activations += 1 }, input: harness.release)
    #expect(activations == 1)
  }

  @Test func branchReplacementCannotReceiveRelease() {
    let harness = Harness()
    var activations = 0
    func content(_ first: Bool) -> VStack {
      VStack {
        if first {
          Button("First") { activations += 1 }
        } else {
          Button("Second") { activations += 1 }
        }
      }
    }
    harness.render(content(true), input: harness.press)
    let original = harness.context.interaction.pressedLeaf
    harness.render(content(false), input: harness.release)
    #expect(activations == 0)
    #expect(harness.context.interaction.pressedLeaf == nil)
    #expect(harness.context.interaction.selectedLeafID != original)
  }

  @Test func removalAndReinsertionCancelPress() {
    let harness = Harness()
    var activations = 0
    let button = Button("Button") { activations += 1 }
    harness.render(button, input: harness.press)
    harness.render(EmptyBlock(), input: InputState(pointerDown: true))
    #expect(harness.context.interaction.pressedLeaf == nil)
    #expect(harness.context.interaction.selectedLeafID == nil)
    harness.render(button, input: harness.release)
    #expect(activations == 0)
  }

  @Test func releaseUsesCurrentActionAndDoesNotReplayIt() {
    let harness = Harness()
    var oldActions = 0
    var newActions = 0
    harness.render(Button("Button") { oldActions += 1 }, input: harness.press)
    harness.render(Button("Button") { newActions += 1 }, input: harness.release)
    harness.render(Button("Button") { newActions += 1 })
    #expect(oldActions == 0)
    #expect(newActions == 1)
  }

  @Test func removedDefaultActionCannotReceiveSubmit() {
    let harness = Harness()
    var activations = 0
    harness.render(Button("Submit", role: .defaultAction) { activations += 1 })
    harness.render(EmptyBlock(), input: InputState(commands: [.action(.submit)]))
    #expect(activations == 0)
  }

  @Test func explicitAndStructuralIDsCannotAlias() {
    let context = RenderContext()
    #expect(context.widgetID != WidgetID(rawValue: 0))
    #expect(context.widgetID == context.widgetID)
    #expect(context.childScope(0).widgetID != context.childScope(1).widgetID)
  }

  private struct Item: Identifiable { let id: Int }

  private struct ItemButton: Block {
    let item: Item
    var body: some Block { Button(String(item.id)) {} }
  }

  @Test func keyedComponentInstancesKeepIndependentFocus() {
    let harness = Harness()
    func content(_ ids: [Int]) -> VStack {
      VStack {
        ForEach(ids.map { Item(id: $0) }) { item in ItemButton(item: item) }
      }
    }
    harness.render(content([1, 2]), input: harness.press)
    let first = harness.context.interaction.pressedLeaf
    harness.render(content([2, 3, 1]), input: InputState(pointerPosition: Point(x: 5, y: 5), pointerDown: true))
    #expect(harness.context.interaction.pressedLeaf == first)
    #expect(harness.context.interaction.selectedLeafID == first)
    #expect(harness.context.interaction.selection == [0, 2])
  }

  @Test func implicitTextFieldPreservesEditingAcrossRebuilds() {
    let harness = Harness()
    var text = "hello"
    func field(_ placeholder: String) -> TextField {
      TextField(placeholder, text: { text }, onChange: { text = $0 })
    }
    harness.render(field("Before"))
    harness.render(field("Before"), input: InputState(commands: [.action(.activate)]))
    let id = harness.context.interaction.editingLeaf
    #expect(id != nil)
    harness.render(field("After"), input: InputState(textEvents: [.insert("!")]))
    #expect(text == "hello!")
    #expect(harness.context.interaction.editingLeaf == id)
    harness.render(EmptyBlock(), input: InputState(textEvents: [.insert("ignored")]))
    #expect(text == "hello!")
    #expect(harness.context.interaction.editingLeaf == nil)
  }

  @Test func implicitScrollViewsHaveIndependentOffsets() {
    let harness = Harness()
    func content() -> HStack {
      HStack {
        ScrollView { Text("left").sizing(y: .fixed(500)) }
        ScrollView { Text("right").sizing(y: .fixed(500)) }
      }
    }
    harness.render(content())
    harness.render(
      content(),
      input: InputState(
        pointerPosition: Point(x: 5, y: 5),
        scrollDelta: Point(x: 0, y: -30)))
    let offsets = harness.context.interaction.scrollOffsets
    #expect(offsets.count == 2)
    #expect(offsets.values.sorted() == [0, 30])
    harness.render(content())
    #expect(harness.context.interaction.scrollOffsets == offsets)
  }

  @Test func implicitLazyStackAndInteractiveRegisterIndependently() {
    let harness = Harness()
    var activations = 0
    let controller = ScrollViewController()
    func content() -> LazyVStack {
      LazyVStack(data: [Item(id: 1), Item(id: 2)], rowHeight: 40, controller: controller) { item in
        Interactive(action: { activations += item.id }) { _ in Text(String(item.id)) }
      }
    }
    harness.render(content(), input: harness.press)
    harness.render(content(), input: harness.release)
    #expect(activations == 1)
    #expect(harness.context.interaction.buttonActions.count == 2)
    #expect(harness.context.interaction.scrollOffsets.count == 1)
  }

  @Test func selectableTextUsesIdentityRatherThanCoordinates() {
    let harness = Harness()
    func content(_ first: Bool) -> VStack {
      VStack {
        if first { Text("first").selectable() } else { Text("second").selectable() }
      }
    }
    harness.render(content(true))
    let selection = harness.context.selection
    let original = selection.layoutRegistry.entry(at: Point(x: 1, y: 1))!.0
    selection.selectAll(at: Point(x: 1, y: 1))
    #expect(selection.selection(for: original) != nil)
    harness.render(content(false))
    let replacement = selection.layoutRegistry.entry(at: Point(x: 1, y: 1))!.0
    #expect(original != replacement)
    #expect(selection.selection(for: replacement) == nil)
  }

  @Test func focusRequestBeforeTraversalBindsWithoutChangingIdentity() {
    let harness = Harness()
    let target = FocusTarget()
    let field = TextField(text: { "hello" }, onChange: { _ in })
    let expected = BlockEngine.resolve(field, context: harness.context).context.widgetID
    target.focus(editing: true)
    harness.render(field.padding(4).focusTarget(target))
    #expect(harness.context.interaction.editingLeaf == expected)
    #expect(target.pendingEditing == nil)
    let generation = harness.context.interaction.editingSessionGeneration
    harness.render(field.focusTarget(target))
    #expect(harness.context.interaction.editingSessionGeneration == generation)
  }

  @Test func focusRequestAfterTraversalRequestsRedrawAndResolves() {
    let harness = Harness()
    let target = FocusTarget()
    func content() -> VStack {
      VStack {
        Button("First") {}
        Button("Second") {}.focusTarget(target)
      }
    }
    harness.render(content())
    let first = harness.context.interaction.selectedLeafID
    _ = harness.context.interaction.consumeRedrawRequest()
    target.focus()
    #expect(harness.context.interaction.consumeRedrawRequest())
    harness.render(content())
    #expect(harness.context.interaction.selectedLeafID != first)
    #expect(harness.context.interaction.selection == [0, 1])
  }

  @Test func focusBindingInvalidatesOnRemovalAndRebindsAfterMove() {
    let harness = Harness()
    let target = FocusTarget()
    let field = TextField(text: { "hello" }, onChange: { _ in }).focusTarget(target)
    target.focus(editing: true)
    harness.render(field)
    let original = harness.context.interaction.editingLeaf
    target.focus(editing: true)
    harness.render(EmptyBlock())
    #expect(target.interaction == nil)
    #expect(target.pendingEditing == nil)
    #expect(harness.context.interaction.editingLeaf == nil)
    target.focus(editing: true)
    harness.render(VStack { field })
    #expect(harness.context.interaction.editingLeaf != nil)
    #expect(harness.context.interaction.editingLeaf != original)
  }

  @Test func measurementDoesNotBindOrConsumeFocusRequest() {
    let target = FocusTarget()
    target.focus()
    let context = RenderContext()
    _ = BlockEngine.measure(
      Button("Button") {}.focusTarget(target),
      proposal: Size(width: 100, height: 100), context: context)
    #expect(target.interaction == nil)
    #expect(target.pendingEditing == false)
    #expect(context.interaction.buildingFocusTargets.isEmpty)
  }

  @Test func removedScrollAndSelectionStateDoNotReturn() {
    let harness = Harness()
    let controller = ScrollViewController()
    func content() -> ScrollView {
      ScrollView(controller: controller) { Text("hello").selectable().sizing(y: .fixed(500)) }
    }
    harness.render(content())
    harness.context.selection.selectAll(at: Point(x: 1, y: 1))
    controller.scroll(to: 30)
    harness.render(content())
    #expect(harness.context.interaction.scrollOffsets.values.contains(30))
    harness.render(EmptyBlock())
    #expect(harness.context.interaction.scrollOffsets.isEmpty)
    #expect(harness.context.selection.selectedText() == nil)
    harness.render(content())
    #expect(harness.context.interaction.scrollOffsets.values.allSatisfy { $0 == 0 })
    #expect(harness.context.selection.selectedText() == nil)
  }

  @Test func virtualizedPressDoesNotReviveWhenRowReturns() {
    let harness = Harness()
    let controller = ScrollViewController()
    var activations = 0
    func content() -> LazyVStack {
      LazyVStack(data: (0..<20).map { Item(id: $0) }, rowHeight: 40, controller: controller) { item in
        Button(String(item.id)) { activations += 1 }
      }
    }
    harness.render(content(), input: harness.press)
    let original = harness.context.interaction.pressedLeaf
    controller.scroll(to: 400)
    harness.render(content(), input: InputState(pointerDown: true))
    #expect(harness.context.interaction.pressedLeaf == nil)
    controller.scrollToTop()
    harness.render(content(), input: harness.release)
    #expect(harness.context.interaction.tree?.findLeaf(original!) != nil)
    #expect(activations == 0)
  }

}
