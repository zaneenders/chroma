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
    h.move(.stepIn)
    #expect(h.state.session.input.isEditing)
    h.renderer.render(input: InputState(textEvents: [.insert("Keep this thought"), .endEditing]))
    #expect(h.state.session.draft == "Keep this thought")
    h.move(.sectionLeft)
    #expect(h.contains("Window / Sessions"))
    h.move(.stepIn, .down, .stepIn)
    #expect(h.state.selectedSession == 1)
    h.move(.sectionRight, .stepIn, .down, .stepIn, .stepIn)
    #expect(h.state.session.input.isEditing)
    h.renderer.render(input: InputState(textEvents: [.insert("Another thought"), .endEditing]))
    h.move(.sectionLeft, .stepIn, .up, .stepIn)
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
