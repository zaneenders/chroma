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

}
