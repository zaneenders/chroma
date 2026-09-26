import Testing

@testable import Chroma

@MainActor
struct HierarchicalNavigationTests {
  @MainActor private final class Harness {
    let context = RenderContext()
    let producer = FrameProducer()
    func render(_ content: any Block, _ commands: [Command] = [], text: [TextEditEvent] = []) {
      _ = producer.render(
        content: content, viewport: Size(width: 800, height: 600),
        input: InputState(commands: commands, textEvents: text), context: context, onChange: {})
    }
  }

  @Test func directionalExitLandsOnSectionAndEntryRestoresOneLevel() {
    let h = Harness()
    let input = FocusTarget()
    let session = FocusTarget()
    let content = HStack(spacing: 20) {
      Group("Sessions") {
        VStack {
          Button("Session") {}.focusTarget(session)
          Button("Another") {}
        }
      }.sizing(x: .fixed(200), y: .grow)
      Group("Conversation") {
        VStack {
          Group("History") { Button("Message") {} }.sizing(x: .grow, y: .grow)
          Group("Composer") {
            HStack {
              TextField(text: { "" }, onChange: { _ in }).focusTarget(input)
              Button("Send") {}
            }
          }
        }
      }.sizing(x: .grow, y: .grow)
    }
    h.render(content)
    input.focus()
    h.render(content)
    #expect(input.isFocused)
    h.render(content, [.navigation(.left)])
    #expect(h.context.navigationBreadcrumb == ["Window", "Sessions"])
    #expect(!session.isFocused)
    h.render(content, [.navigation(.stepIn)])
    #expect(session.isFocused)
    h.render(content, [.navigation(.right)])
    #expect(h.context.navigationBreadcrumb == ["Window", "Conversation"])
    h.render(content, [.navigation(.stepIn)])
    #expect(h.context.navigationBreadcrumb == ["Window", "Conversation", "Composer"])
    #expect(!input.isFocused)
    h.render(content, [.navigation(.stepIn)])
    #expect(input.isFocused)
  }

  @Test func wrongAxisDoesNotFallBackToNextChild() {
    let h = Harness()
    let first = FocusTarget()
    let second = FocusTarget()
    let content = Group {
      VStack {
        Button("First") {}.focusTarget(first)
        Button("Second") {}.focusTarget(second)
      }
    }
    h.render(content)
    first.focus()
    h.render(content)
    h.render(content, [.navigation(.right)])
    #expect(first.isFocused)
    #expect(!second.isFocused)
    h.render(content, [.navigation(.down)])
    #expect(second.isFocused)
  }

  @Test func enterActivatesAndEditingExitKeepsInputSelected() {
    let h = Harness()
    let input = FocusTarget()
    let button = FocusTarget()
    var text = ""
    var activations = 0
    let content = Group {
      HStack {
        TextField(text: { text }, onChange: { text = $0 }).focusTarget(input)
        Button("Send") { activations += 1 }.focusTarget(button)
      }
    }
    h.render(content)
    input.focus()
    h.render(content)
    h.render(content, [.navigation(.stepIn)])
    #expect(input.isEditing)
    h.render(content, [.navigation(.right)], text: [.insert("sldfjk")])
    #expect(text == "sldfjk")
    #expect(input.isFocused)
    h.render(content, text: [.endEditing])
    #expect(!input.isEditing && input.isFocused)
    h.render(content, [.navigation(.right)])
    h.render(content, [.navigation(.stepIn)])
    #expect(button.isFocused)
    #expect(activations == 1)
  }

  @Test func selectingOffscreenMessageGroupRevealsItWithoutEntering() {
    let h = Harness()
    let controller = ScrollViewController()
    let content = ScrollView("History", controller: controller) {
      ForEach(0..<12, id: \.self) { index in
        Group("Message \(index)") {
          Button("Read") {}
        }.sizing(x: .grow, y: .fixed(100))
      }
    }
    h.render(content)
    h.render(content, [.navigation(.down)])
    h.render(content, [.navigation(.stepIn)])
    for _ in 0..<8 { h.render(content, [.navigation(.down)]) }
    h.render(content)
    #expect(h.context.navigationBreadcrumb.last == "Message 8")
    #expect(h.context.interaction.selectedLeafID == nil)
    #expect(controller.offset > 0)
    let offset = controller.offset
    h.render(content, [.navigation(.stepOut)])
    #expect(controller.offset == offset)
    h.render(content, [.navigation(.stepIn)])
    #expect(h.context.navigationBreadcrumb.last == "Message 8")
    #expect(controller.offset == offset)
  }
}

extension HierarchicalNavigationTests {
  @Test func removingSelectedGroupDoesNotEnterItsReplacement() {
    let h = Harness()
    var ids = [0, 1, 2]
    let content = DeferredBlock {
      Group("Sections") {
        VStack {
          ForEach(ids, id: \.self) { id in
            Group("Section \(id)") { Button("Use") {} }
          }
        }
      }
    }
    h.render(content)
    h.render(content, [.navigation(.down), .navigation(.stepIn), .navigation(.down)])
    #expect(h.context.navigationBreadcrumb.last == "Section 1")
    ids.remove(at: 1)
    h.render(content)
    #expect(h.context.navigationBreadcrumb.last == "Section 2")
    #expect(h.context.interaction.selectedLeafID == nil)
  }

  @Test func hoverDoesNotChangeKeyboardSelectionOrGroupMemory() {
    let h = Harness()
    let first = FocusTarget()
    let second = FocusTarget()
    let content = Group("Controls") {
      HStack {
        Button("First") {}.focusTarget(first)
        Button("Second") {}.focusTarget(second)
      }
    }
    h.render(content)
    first.focus()
    h.render(content)
    let tree = h.context.interaction.tree!
    let rect = tree.node(at: tree.findLeaf(second.boundID!)!)!.rect
    _ = h.producer.render(
      content: content, viewport: Size(width: 800, height: 600),
      input: InputState(pointerPosition: Point(x: rect.minX + 2, y: rect.minY + 2)),
      context: h.context, onChange: {})
    #expect(first.isFocused)
    h.render(content, [.navigation(.stepOut), .navigation(.stepIn)])
    #expect(first.isFocused)
  }

  @Test func rootCommandsRemainAvailableBeforeASectionIsSelected() {
    let h = Harness()
    var calls = 0
    let content = TupleBlock(children: [
      HStack {
        Group("Left") { Button("One") {} }
        Group("Right") { Button("Two") {} }
      }.onCommand(.application("capture")) {
        calls += 1
        return .handled
      }
    ])
    h.render(content)
    h.render(content, [.application("capture")])
    #expect(calls == 1)
    #expect(h.context.interaction.navigationPath.isEmpty)
  }
}
