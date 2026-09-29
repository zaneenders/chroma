import Chroma
import ChromaTesting
import Testing

@testable import DemoContent

@MainActor
struct KeyboardFlowTests {
  @Test func enteringComposerAndTypingUsesKeyboardBindings() {
    let state = WorkspaceState()
    let ui = NavigationTestHost(
      content: WorkspaceDemo(state: state, gallery: PerformanceDemoState(itemCount: 100)),
      size: Size(width: 1200, height: 820))

    #expect(!state.session.input.isFocused)
    ui.press("j", "j", "k", "l", "j", "l")
    #expect(state.session.input.isFocused)
    #expect(!state.session.input.isEditing)
    ui.press(.enter)
    #expect(state.session.input.isEditing)
    ui.press("h", "i")
    #expect(state.session.draft == "hi")
    ui.press(.escape)
    #expect(state.session.input.isFocused && !state.session.input.isEditing)
  }

  @Test func steppingIntoSessionAndActivatingOpensIt() {
    let state = WorkspaceState()
    let ui = NavigationTestHost(
      content: WorkspaceDemo(state: state, gallery: PerformanceDemoState(itemCount: 100)),
      size: Size(width: 1200, height: 820))

    ui.press("j", "j", "l", "j", "l", .enter)
    #expect(state.selectedSession == 1)
    #expect(state.status.contains("Field notes"))
  }
}

@MainActor
@Test func demoAppLaunchesWithItsKeyboardBindings() throws {
  let ui = try NavigationTestHost(app: DemoApplication(itemCount: 100, shortcutModifier: .command))
  #expect(ui.host.viewport == Size(width: 1200, height: 820))
  #expect(ui.host.resolve(KeyboardInput(chord: KeyChord("j"), text: "j")) == .command(.navigation(.down)))
  ui.press("j", "j", "l", "j", "l", .enter)
  #expect(
    ui.host.lastFrame?.commands.contains { command in
      if case .text(_, let text, _, _) = command { return text.contains("Opened Field notes") }
      return false
    } == true)
}
