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

}
