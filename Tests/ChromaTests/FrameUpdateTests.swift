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
    renderer.build = { buffer, context in
      let node169 = buffer.text(Text(model.text), context: context.childScope(0))
      let node170 = buffer.button(
        Button("Change", id: WidgetID("button")) {
          model.actions += 1
          model.text = "after"
        }, context: context.childScope(1))
      return buffer.stack([node169, node170], axis: .vertical, context: context)
    }
    renderer.render()
    let frame = renderer.render(
      input: InputState(commands: [.navigation(.down), .navigation(.down), .action(.activate)]))
    #expect(model.actions == 1)
    #expect(
      frame.paintSnapshot.contains { command in
        if case .text(_, let text, _, _) = command { return text == "after" }
        return false
      })
    renderer.render()
    #expect(model.actions == 1)
  }

  @Test func textEditingUpdatesEarlierSiblingBeforeDrawing() {
    let model = Model()
    let renderer = HeadlessHost()
    renderer.build = { buffer, context in
      let node172 = buffer.text(Text(model.text), context: context.childScope(0))
      let node173 = buffer.textEditor(
        TextEditor(singleLine: true, text: { model.text }, onChange: { model.text = $0 }),
        context: context.childScope(1))
      return buffer.stack([node172, node173], axis: .vertical, context: context)
    }
    renderer.render()
    renderer.render(
      input: InputState(commands: [.navigation(.down), .navigation(.down), .action(.activate)]))
    let frame = renderer.render(input: InputState(textEvents: [.insert("!")]))
    #expect(model.text == "before!")
    #expect(
      frame.paintSnapshot.contains { command in
        if case .text(_, let text, _, _) = command { return text == "before!" }
        return false
      })
    renderer.close()
  }

  @Test(ControlledObservationDelivery())
  func externalScrollRequestInvalidatesObservedFrame() async {
    let controller = ScrollViewController()
    let renderer = HeadlessHost()
    renderer.build = { buffer, context in
      let node176 = buffer.scrollView(
        ScrollView(
          controller: controller,
          build: { buffer, context in
            return buffer.text(Text("hello"), context: context)
          }), context: context.keyed(WidgetID("scroll")))
      return node176
    }
    var requests = 0
    renderer.onRedrawRequested = { requests += 1 }
    renderer.render()
    controller.scrollToBottom()
    await drainObservationChanges()
    #expect(requests == 1)
    renderer.close()
  }

}
