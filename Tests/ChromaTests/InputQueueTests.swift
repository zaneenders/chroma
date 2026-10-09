import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct InputQueueTests {
  @Test(arguments: [false, true])
  func firstPresentationDrainsOlderEventsBeforeExplicitInput(scheduled: Bool) {
    let host = HeadlessHost()
    defer { host.close() }
    var received: [String] = []
    host.build = { buffer, context in
      context.registerInputHandler { input in
        for case .insert(let text) in input.textEvents { received.append(text) }
      }
      return buffer.text(Text("Input observer"), context: context)
    }
    host.sendInput(InputState(textEvents: [.insert("before")]))
    if scheduled {
      #expect(host.renderIfNeeded() != nil)
      host.sendInput(InputState(textEvents: [.insert("explicit")]))
    } else {
      host.render(input: InputState(textEvents: [.insert("explicit")]))
    }
    #expect(received == ["before", "explicit"])
    host.sendInput(InputState(textEvents: [.insert("after")]))
    host.render()
    #expect(received == ["before", "explicit", "after"])
    #expect(host.renderIfNeeded() == nil)
  }

  @Test func explicitSnapshotDrainsInitialMixedRawAndResolvedInput() {
    let host = HeadlessHost()
    defer { host.close() }
    let focus = FocusTarget()
    var text = ""
    host.build = { buffer, context in
      buffer.focus(focus, context: context) { buffer, context in
        buffer.textEditor(TextEditor(text: { text }, onChange: { text = $0 }), context: context)
      }
    }
    focus.focus(editing: true)
    host.sendInput(InputState(textEvents: [.insert("a")]))
    host.runtime.handleKeyboardInput(KeyboardInput(chord: KeyChord("b"), text: "b")) { resolved in
      if case .text(let event) = resolved { host.sendInput(InputState(textEvents: [event])) }
    }
    host.sendInput(InputState(textEvents: [.insert("c")]))
    host.render()
    #expect(text == "abc")
    #expect(host.renderIfNeeded() == nil)
    host.render()
    #expect(text == "abc")
  }

  @Test func nestedSubmitWaitsForOuterInputAndRunsExactlyOnce() {
    let host = HeadlessHost()
    defer { host.close() }
    let focus = FocusTarget()
    var order: [String] = []
    host.build = { buffer, context in
      context.registerInputHandler { input in
        if !input.commands.isEmpty { order.append("outer observer") }
        if !input.textEvents.isEmpty { order.append("nested observer") }
      }
      let editor = buffer.focus(focus, context: context) { buffer, context in
        buffer.textEditor(
          TextEditor(text: { "" }, onChange: { _ in }, onSubmit: { _ in order.append("submit") }), context: context)
      }
      return buffer.onCommand(editor, .application("nested"), context: context) {
        order.append("outer begin")
        host.sendInput(InputState(textEvents: [.submit]))
        order.append("outer end")
        return .handled
      }
    }
    focus.focus(editing: true)
    host.render()
    host.sendInput(InputState(commands: [.application("nested")]))
    #expect(order == ["outer begin", "outer end", "outer observer", "submit", "nested observer"])
    host.render()
    #expect(order.count == 5)
  }

  @Test(arguments: [false, true])
  func queuedAndNestedPointerEdgesKeepTheirOrder(nestedRelease: Bool) {
    let host = HeadlessHost()
    defer { host.close() }
    let point = Point(x: 5, y: 5)
    var actions = 0
    var observed: [String] = []
    host.build = { buffer, context in
      context.registerInputHandler { input in
        if input.pointerPressed {
          observed.append("press")
          #expect(host.runtime.interaction.input.pointerPressed)
          #expect(host.runtime.interaction.dragOrigin == point)
          if nestedRelease { host.sendInput(InputState(pointerPosition: point, pointerReleased: true)) }
          #expect(host.runtime.interaction.input.pointerPressed)
        }
        if input.pointerReleased {
          observed.append("release")
          #expect(host.runtime.interaction.dragOrigin == point)
        }
      }
      return buffer.button(Button("Action") { actions += 1 }, context: context)
    }
    host.sendInput(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    if !nestedRelease { host.sendInput(InputState(pointerPosition: point, pointerReleased: true)) }
    host.render()
    #expect(observed == ["press", "release"])
    #expect(actions == 1)
    #expect(host.runtime.interaction.dragOrigin == nil)
    #expect(host.runtime.interaction.input.pointerPosition == point)
    #expect(!host.runtime.interaction.input.pointerReleased)
    host.render()
    #expect(actions == 1)
    #expect(observed.count == 2)
  }

  @Test func nestedRawKeyResolvesAfterOuterCallbackFinishes() {
    let host = HeadlessHost()
    defer { host.close() }
    var command = Command.application("old")
    var received: [String] = []
    host.build = { buffer, context in
      let label = buffer.text(Text("Commands"), context: context)
      let keys = buffer.keyBindings(label, KeyBindings { bind("x", to: command) }, context: context)
      let old = buffer.onCommand(keys, .application("old"), context: context) {
        received.append("old")
        return .handled
      }
      let new = buffer.onCommand(old, .application("new"), context: context) {
        received.append("new")
        return .handled
      }
      return buffer.onCommand(new, .application("outer"), context: context) {
        host.runtime.handleKeyboardInput(KeyboardInput(chord: KeyChord("x"), text: "x")) { resolved in
          if case .command(let command) = resolved { host.sendInput(InputState(commands: [command])) }
        }
        command = .application("new")
        return .handled
      }
    }
    host.render()
    host.sendInput(InputState(commands: [.application("outer")]))
    #expect(received == ["new"])
  }

  @Test(arguments: [false, true])
  func rootReplacementPreservesLatestPointerAndDrainsNestedInput(nestedInput: Bool) {
    let host = HeadlessHost()
    defer { host.close() }
    let point = Point(x: 25, y: 35)
    var received: [String] = []
    host.build = { buffer, context in
      let label = buffer.text(Text("Old"), context: context)
      return buffer.onCommand(label, .application("replace"), context: context) {
        host.build = { buffer, context in
          context.registerInputHandler { input in
            for case .insert(let text) in input.textEvents { received.append(text) }
          }
          return buffer.text(Text("New!"), context: context)
        }
        if nestedInput {
          host.sendInput(InputState(pointerPosition: point, pointerDown: true, textEvents: [.insert("nested")]))
        }
        return .handled
      }
    }
    host.render()
    host.sendInput(InputState(pointerPosition: point, pointerDown: true, commands: [.application("replace")]))
    #expect(received == (nestedInput ? ["nested"] : []))
    let frame = host.render()
    #expect(host.runtime.interaction.input.pointerPosition == point)
    #expect(host.runtime.interaction.input.pointerDown)
    #expect(
      frame.commands.filter {
        if case .quad(let quad) = $0 { return quad.texture == .fontAtlas }
        return false
      }.count == 4)
    #expect(host.renderIfNeeded() == nil)
  }

  @Test(arguments: [false, true])
  func wheelCancelsOnlyRevealRequestsMadeBeforeTheEvent(revealAfterInput: Bool) {
    let host = HeadlessHost(size: Size(width: 100, height: 100))
    defer { host.close() }
    let controller = ScrollViewController()
    host.build = { buffer, context in
      context.registerInputHandler { input in
        if revealAfterInput && input.scrollDelta != .zero {
          controller.scrollToVisible(Rect(x: 0, y: 500, width: 10, height: 10))
        }
      }
      return buffer.scrollView(
        ScrollView(data: 0..<100, rowHeight: 10, controller: controller) { buffer, context, _ in
          buffer.text(Text("Row"), context: context)
        }, context: context)
    }
    host.render()
    controller.scrollToVisible(Rect(x: 0, y: 500, width: 10, height: 10))
    host.sendInput(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -12)))
    #expect((controller.request != nil) == revealAfterInput)
    host.renderIfNeeded()
    #expect(controller.offset == (revealAfterInput ? 422 : 12))
    #expect(controller.request == nil)
    #expect(host.renderIfNeeded() == nil)
  }

}
