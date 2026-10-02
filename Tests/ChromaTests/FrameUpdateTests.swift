import ChromaTesting
import Observation
import Testing

@testable import Chroma

@MainActor
struct FrameUpdateTests {
  @Observable final class Model {
    var text = "before"
    var actions = 0
  }

  @Test func actionUpdatesEarlierSiblingInTheSameFrame() {
    let model = Model()
    let renderer = HeadlessHost()
    renderer.content = DeferredBlock {
      VStack {
        Text(model.text)
        Button("Change", id: WidgetID("button")) {
          model.actions += 1
          model.text = "after"
        }
      }
    }
    renderer.render()
    let frame = renderer.render(
      input: InputState(commands: [.navigation(.down), .navigation(.down), .action(.activate)]))
    #expect(model.actions == 1)
    #expect(
      frame.commands.contains { command in
        if case .text(_, let text, _, _) = command { return text == "after" }
        return false
      })
    renderer.render()
    #expect(model.actions == 1)
  }

  @Test func textEditingUpdatesEarlierSiblingBeforeDrawing() {
    let model = Model()
    let renderer = HeadlessHost()
    renderer.content = DeferredBlock {
      VStack {
        Text(model.text)
        TextEditor(singleLine: true, text: { model.text }, onChange: { model.text = $0 })
      }
    }
    renderer.render()
    renderer.render(
      input: InputState(commands: [.navigation(.down), .navigation(.down), .action(.activate)]))
    let frame = renderer.render(input: InputState(textEvents: [.insert("!")]))
    #expect(model.text == "before!")
    #expect(
      frame.commands.contains { command in
        if case .text(_, let text, _, _) = command { return text == "before!" }
        return false
      })
    renderer.close()
  }

  @Test(ControlledObservationDelivery())
  func externalScrollRequestInvalidatesObservedFrame() async {
    let controller = ScrollViewController()
    let renderer = HeadlessHost()
    renderer.content = ScrollView(controller: controller) {
      Text("hello")
    }.id(WidgetID("scroll"))
    var requests = 0
    renderer.onRedrawRequested = { requests += 1 }
    renderer.render()
    controller.scrollToBottom()
    await drainObservationChanges()
    #expect(requests == 1)
    renderer.close()
  }

}
