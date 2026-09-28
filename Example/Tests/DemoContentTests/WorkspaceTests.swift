import Chroma
import HeadlessBackend
import Testing

@testable import DemoContent

@MainActor
struct WorkspaceTests {
  @MainActor private final class Harness {
    let state = WorkspaceState()
    let renderer = HeadlessRenderer(size: Size(width: 1200, height: 820))
    init() {
      let state = state
      let gallery = PerformanceDemoState(itemCount: 100)
      renderer.content = DeferredBlock { WorkspaceDemo(state: state, gallery: gallery) }
      renderer.render()
    }
    @discardableResult func move(_ commands: NavigationCommand...) -> HeadlessFrame {
      for command in commands { renderer.render(input: InputState(commands: [.navigation(command)])) }
      return renderer.render()
    }
    func contains(_ text: String) -> Bool {
      renderer.render().commands.contains {
        if case .text(_, let value, _, _) = $0 { return value.contains(text) }
        return false
      }
    }
  }

  @Test func keyboardOnlyDraftSessionRoundTrip() {
    let h = Harness()
    h.move(.down, .down, .right, .stepIn, .down, .stepIn)
    #expect(h.state.session.input.isFocused)
    h.renderer.render(input: InputState(commands: [.action(.activate)]))
    #expect(h.state.session.input.isEditing)
    h.renderer.render(input: InputState(textEvents: [.insert("Keep this thought"), .endEditing]))
    #expect(h.state.session.draft == "Keep this thought")
    h.move(.stepOut, .sectionLeft)
    #expect(h.contains("Window / Sessions"))
    h.move(.stepIn, .down, .stepIn)
    #expect(h.state.selectedSession == 1)
    h.move(.sectionRight, .stepIn, .down, .stepIn)
    h.renderer.render(input: InputState(commands: [.action(.activate)]))
    #expect(h.state.session.input.isEditing)
    h.renderer.render(input: InputState(textEvents: [.insert("Another thought"), .endEditing]))
    h.move(.stepOut, .sectionLeft, .stepIn, .up, .stepIn)
    #expect(h.state.selectedSession == 0)
    h.move(.sectionRight, .stepIn)
    #expect(h.contains("Window / Conversation / Composer"))
    #expect(!h.state.session.input.isFocused)
    h.move(.stepIn)
    #expect(h.state.session.input.isFocused)
    #expect(h.state.session.draft == "Keep this thought")
    #expect(h.state.sessions[1].draft == "Another thought")
  }

  @Test func historyPositionSurvivesSessionsAndNewMessages() {
    let h = Harness()
    h.state.open(h.state.sessions[2])
    h.renderer.render()
    h.move(.down, .down, .right, .stepIn, .stepIn)
    for _ in 0..<16 { h.move(.down) }
    h.renderer.render()
    let offset = h.state.session.scroll.offset
    #expect(offset > 0)
    h.move(.stepOut, .stepOut, .left, .stepIn, .stepIn)
    #expect(h.state.selectedSession == 0)
    h.move(.down, .down, .stepIn)
    #expect(h.state.selectedSession == 2)
    h.renderer.render()
    #expect(h.state.session.scroll.offset == offset)
    h.move(.sectionRight, .stepIn, .stepIn)
    #expect(h.contains("Message 17"))
    #expect(h.state.session.scroll.offset == offset)
    h.state.session.draft = "A new message"
    h.state.session.send()
    h.renderer.render()
    #expect(h.state.session.scroll.offset == offset)
  }

  @Test func messageActionsAreKeyboardReachable() {
    let h = Harness()
    h.move(.down, .down, .right, .stepIn, .stepIn, .stepIn, .down, .stepIn)
    #expect(h.state.session.messages[0].saved)
    h.move(.right, .stepIn)
    #expect(h.state.session.draft == "> " + h.state.session.messages[0].text)
    #expect(h.contains("Quoted into the composer"))
  }

  @Test func composerKeepsMultilineDraftUntilSendIsActivated() throws {
    let h = Harness()
    let count = h.state.session.messages.count
    h.state.session.input.focus(editing: true)
    h.renderer.render()
    h.renderer.render(input: InputState(textEvents: [.insert("First line"), .submit, .insert("Second line")]))
    #expect(h.state.session.draft == "First line\nSecond line")
    #expect(h.state.session.messages.count == count)
    h.renderer.render(input: InputState(textEvents: [.endEditing]))
    #expect(!h.state.session.input.isEditing)
    #expect(h.state.status == "Draft kept. Select Send when you are ready.")
    let position = try #require(
      h.renderer.render().commands.compactMap { command -> Point? in
        if case .text(let point, let text, _, _) = command, text == "Send" { return point }
        return nil
      }.first)
    let click = Point(x: position.x + 2, y: position.y + 2)
    h.renderer.render(input: InputState(pointerPosition: click, pointerDown: true, pointerPressed: true))
    h.renderer.render(input: InputState(pointerPosition: click, pointerReleased: true))
    try #require(h.state.session.messages.count == count + 2)
    #expect(h.state.session.messages[count].text == "First line\nSecond line")
    #expect(h.state.session.draft.isEmpty)
  }

  @Test func emptySendIsIgnoredAndRepliesAreLocal() {
    let state = WorkspaceState()
    let count = state.session.messages.count
    state.session.draft = "   "
    state.session.send()
    #expect(state.session.messages.count == count)
    state.session.draft = "Hello"
    state.session.send()
    #expect(state.session.messages.count == count + 2)
    #expect(state.session.messages[count].text == "Hello")
    #expect(state.session.draft.isEmpty)
    #expect(state.sessions[1].messages.count == 4)
  }

  @Test func workspaceStartsInMoveModeWithoutAnimation() {
    let h = Harness()
    #expect(h.contains("MOVE   /   Window"))
    #expect(!h.renderer.needsAnimationFrame)
    #expect(h.contains("First steps"))
    #expect(h.contains("Render gallery"))
  }
}
