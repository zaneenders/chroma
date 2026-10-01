import Chroma
import ChromaTesting
import Testing

@testable import DemoContent

@MainActor
struct StandaloneApplicationTests {
  private func checkApp<A: App>(_ app: A, title: String) throws {
    #expect(app.title == title)
    let ui = try NavigationTestHost(app: app)
    #expect(!ui.host.render().commands.isEmpty)
    #expect(app.keyBindings.command(for: KeyChord("1", modifiers: demoShortcutModifier)) == nil)
    #expect(app.keyBindings.command(for: KeyChord("2", modifiers: demoShortcutModifier)) == nil)
    #expect(app.keyBindings.command(for: KeyChord("c", modifiers: demoShortcutModifier)) == .editing(.copy))
  }

  @Test func playRunsIndependently() throws {
    try checkApp(PlayApplication(state: PlayState(automaticallyTicks: false)), title: "Chroma — Play")
  }

  @Test func chatRunsIndependently() throws {
    try checkApp(
      ChatApplication(state: ChatState(automaticallyStreams: false), shortcutModifier: demoShortcutModifier),
      title: "Chroma — Chat")
  }

  @Test func imageRunsIndependently() throws {
    try checkApp(ImageApplication(), title: "Chroma — Image")
  }
}
