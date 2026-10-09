import Testing

@testable import Chroma

@MainActor
struct HierarchicalNavigationTests {
  @MainActor private final class Harness {
    let runtime = WindowRuntime()
    var context: LayoutContext { runtime.context }
    private var currentContent: LayoutBuilder = { buffer, context in
      return buffer.empty(context: context)
    }

    init() {
      runtime.build = { [unowned self] buffer, context in
        currentContent(&buffer, context)
      }
    }
    func render(_ content: @escaping LayoutBuilder, _ commands: [Command] = [], text: [TextEditEvent] = []) {
      currentContent = content
      _ = runtime.render(
        viewport: Size(width: 800, height: 600),
        input: InputState(commands: commands, textEvents: text), onChange: {})
    }
  }

  @Test func directionalExitLandsOnSectionAndEntryRestoresOneLevel() {
    let h = Harness()
    let input = FocusTarget()
    let session = FocusTarget()
    let content: LayoutBuilder = { buffer, context in
      let node182 = buffer.group("Sessions", context: context.childScope(0)) { buffer, context in
        let node179 = buffer.focus(
          session, context: context.childScope(0).childScope(0),
          content: { buffer, context in
            return buffer.button(Button("Session") {}, context: context)
          })
        let node180 = buffer.button(Button("Another") {}, context: context.childScope(0).childScope(1))
        return buffer.stack([node179, node180], axis: .vertical, context: context.childScope(0))
      }
      let node183 = buffer.sizing(node182, x: .fixed(200), y: .grow, context: context.childScope(0))
      let node193 = buffer.group("Conversation", context: context.childScope(1)) { buffer, context in
        let node185 = buffer.group("History", context: context.childScope(0).childScope(0)) { buffer, context in
          return buffer.button(Button("Message") {}, context: context.childScope(0))
        }
        let node186 = buffer.sizing(node185, x: .grow, y: .grow, context: context.childScope(0).childScope(0))
        let node191 = buffer.group("Composer", context: context.childScope(0).childScope(1)) { buffer, context in
          let node188 = buffer.focus(
            input, context: context.childScope(0).childScope(0),
            content: { buffer, context in
              let node187 = buffer.textEditor(
                TextEditor(singleLine: true, text: { "" }, onChange: { _ in }), context: context)
              return node187
            })
          let node189 = buffer.button(Button("Send") {}, context: context.childScope(0).childScope(1))
          return buffer.stack([node188, node189], axis: .horizontal, context: context.childScope(0))
        }
        return buffer.stack([node186, node191], axis: .vertical, context: context.childScope(0))
      }
      let node194 = buffer.sizing(node193, x: .grow, y: .grow, context: context.childScope(1))
      return buffer.stack([node183, node194], axis: .horizontal, spacing: 20, context: context)
    }
    h.render(content)
    input.focus()
    h.render(content)
    #expect(input.isFocused)
    h.render(content, [.navigation(.sectionLeft)])
    #expect(h.context.navigationBreadcrumb == ["Window", "Sessions"])
    #expect(!session.isFocused)
    h.render(content, [.navigation(.stepIn)])
    #expect(session.isFocused)
    h.render(content, [.navigation(.sectionRight)])
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
    let content: LayoutBuilder = { buffer, context in
      let node201 = buffer.group(context: context) { buffer, context in
        let node197 = buffer.focus(
          first, context: context.childScope(0).childScope(0),
          content: { buffer, context in
            return buffer.button(Button("First") {}, context: context)
          })
        let node199 = buffer.focus(
          second, context: context.childScope(0).childScope(1),
          content: { buffer, context in
            return buffer.button(Button("Second") {}, context: context)
          })
        return buffer.stack([node197, node199], axis: .vertical, context: context.childScope(0))
      }
      return node201
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
    let content: LayoutBuilder = { buffer, context in
      let node207 = buffer.group(context: context) { buffer, context in
        let node203 = buffer.focus(
          input, context: context.childScope(0).childScope(0),
          content: { buffer, context in
            let node202 = buffer.textEditor(
              TextEditor(singleLine: true, text: { text }, onChange: { text = $0 }), context: context)
            return node202
          })
        let node205 = buffer.focus(
          button, context: context.childScope(0).childScope(1),
          content: { buffer, context in
            return buffer.button(Button("Send") { activations += 1 }, context: context)
          })
        return buffer.stack([node203, node205], axis: .horizontal, context: context.childScope(0))
      }
      return node207
    }
    h.render(content)
    input.focus()
    h.render(content)
    h.render(content, [.action(.activate)])
    #expect(input.isEditing)
    h.render(content, [.navigation(.right)], text: [.insert("sldfjk")])
    #expect(text == "sldfjk")
    #expect(input.isFocused)
    h.render(content, text: [.endEditing])
    #expect(!input.isEditing && input.isFocused)
    h.render(content, [.navigation(.stepOut), .navigation(.right)])
    h.render(content, [.navigation(.stepIn)])
    #expect(button.isFocused)
    #expect(activations == 1)
  }

  @Test func sectionMovementLeavesTextCaretAndSelectsNeighboringArea() {
    let h = Harness()
    let editor = FocusTarget()
    let sessions = FocusTarget()
    var text = "hello"
    let content: LayoutBuilder = { buffer, context in
      let node210 = buffer.group("Sessions", context: context.childScope(0)) { buffer, context in
        let node209 = buffer.focus(
          sessions, context: context.childScope(0),
          content: { buffer, context in
            return buffer.button(Button("Session") {}, context: context)
          })
        return node209
      }
      let node211 = buffer.sizing(node210, x: .fixed(200), y: .grow, context: context.childScope(0))
      let node214 = buffer.group("Conversation", context: context.childScope(1)) { buffer, context in
        let node213 = buffer.focus(
          editor, context: context.childScope(0),
          content: { buffer, context in
            return buffer.textEditor(TextEditor(text: { text }, onChange: { text = $0 }), context: context)
          })
        return node213
      }
      let node215 = buffer.sizing(node214, x: .grow, y: .grow, context: context.childScope(1))
      return buffer.stack([node211, node215], axis: .horizontal, context: context)
    }
    h.render(content)
    editor.focus(editing: true)
    h.render(content)
    h.render(content, text: [.endEditing])
    #expect(!editor.isEditing && editor.isFocused)
    #expect(h.context.interaction.editingLeaf != nil)
    h.render(content, [.navigation(.sectionLeft)])
    #expect(h.context.navigationBreadcrumb == ["Window", "Sessions"])
    #expect(h.context.interaction.editingLeaf == nil)
  }

  @Test func shiftSelectsAndCopiesEditorTextInMovementMode() {
    let h = Harness()
    let editor = FocusTarget()
    var text = "hello"
    let content: LayoutBuilder = { buffer, context in
      let node218 = buffer.focus(
        editor, context: context,
        content: { buffer, context in
          return buffer.textEditor(TextEditor(text: { text }, onChange: { text = $0 }), context: context)
        })
      return node218
    }
    h.render(content)
    editor.focus(editing: true)
    h.render(content)
    h.render(content, text: [.endEditing])
    h.render(content, text: [.selectCaretLeft, .selectCaretLeft])
    #expect(h.context.interactionMode == .movement)
    #expect(h.context.interaction.copyText() == "lo")
    h.render(content, [.navigation(.stepOut)])
    #expect(h.context.interaction.copyText() == nil)
  }

  @Test func selectingOffscreenMessageGroupRevealsItWithoutEntering() {
    let h = Harness()
    let controller = ScrollViewController()
    let content: LayoutBuilder = { buffer, context in
      let node224 = buffer.scrollView(
        ScrollView(
          "History", controller: controller,
          build: { buffer, context in
            var children222: [LayoutNode] = []
            for index in 0..<12 {
              let node220 = buffer.group("Message \(index)", context: context.keyed(index)) { buffer, context in
                return buffer.button(Button("Read") {}, context: context.childScope(0))
              }
              let node221 = buffer.sizing(node220, x: .grow, y: .fixed(100), context: context.keyed(index))
              children222.append(node221)
            }
            return buffer.stack(children222, axis: .vertical, spacing: 0, context: context)
          }), context: context)
      return node224
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
    let content: LayoutBuilder = { buffer, context in
      let node230 = buffer.group("Sections", context: context) { buffer, context in
        var children227: [LayoutNode] = []
        for id in ids {
          let node226 = buffer.group("Section \(id)", context: context.childScope(0).childScope(0).keyed(id)) {
            buffer, context in
            return buffer.button(Button("Use") {}, context: context.childScope(0))
          }
          children227.append(node226)
        }
        let node228 = buffer.stack(
          children227, axis: .vertical, spacing: 0, context: context.childScope(0).childScope(0))
        return buffer.stack([node228], axis: .vertical, context: context.childScope(0))
      }
      return node230
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
    let content: LayoutBuilder = { buffer, context in
      let node236 = buffer.group("Controls", context: context) { buffer, context in
        let node232 = buffer.focus(
          first, context: context.childScope(0).childScope(0),
          content: { buffer, context in
            return buffer.button(Button("First") {}, context: context)
          })
        let node234 = buffer.focus(
          second, context: context.childScope(0).childScope(1),
          content: { buffer, context in
            return buffer.button(Button("Second") {}, context: context)
          })
        return buffer.stack([node232, node234], axis: .horizontal, context: context.childScope(0))
      }
      return node236
    }
    h.render(content)
    first.focus()
    h.render(content)
    let tree = h.context.interaction.tree!
    let rect = tree.node(at: tree.findLeaf(second.boundID!)!)!.rect
    _ = h.runtime.render(
      viewport: Size(width: 800, height: 600),
      input: InputState(pointerPosition: Point(x: rect.minX + 2, y: rect.minY + 2)),
      onChange: {})
    #expect(first.isFocused)
    h.render(content, [.navigation(.stepOut), .navigation(.stepIn)])
    #expect(first.isFocused)
  }

  @Test func rootCommandsRemainAvailableBeforeASectionIsSelected() {
    let h = Harness()
    var calls = 0
    let content: LayoutBuilder = { buffer, context in
      let node238 = buffer.group("Left", context: context.childScope(0).childScope(0)) { buffer, context in
        return buffer.button(Button("One") {}, context: context.childScope(0))
      }
      let node240 = buffer.group("Right", context: context.childScope(0).childScope(1)) { buffer, context in
        return buffer.button(Button("Two") {}, context: context.childScope(0))
      }
      let node241 = buffer.stack([node238, node240], axis: .horizontal, context: context.childScope(0))
      let node242 = buffer.onCommand(
        node241, .application("capture"), context: context.childScope(0),
        action: {
          calls += 1
          return .handled
        })
      return buffer.overlay([node242], group: false, context: context)
    }
    h.render(content)
    h.render(content, [.application("capture")])
    #expect(calls == 1)
    #expect(h.context.interaction.navigationPath.isEmpty)
  }
}
