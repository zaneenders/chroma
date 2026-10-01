import Chroma
import ChromaTesting
import Testing

@testable import DemoContent

@MainActor
struct KeyboardFlowTests {
  private func harness() throws -> (DemoState, NavigationTestHost) {
    let state = DemoState(automaticallyUpdates: false)
    let ui = try NavigationTestHost(app: DemoApplication(state: state, shortcutModifier: .command))
    return (state, ui)
  }

  @Test func appLaunchesIntoAnIdleGameWithoutTheGallery() throws {
    let (_, ui) = try harness()
    #expect(ui.host.viewport == Size(width: 1120, height: 840))
    #expect(!ui.host.needsAnimationFrame)
    let text =
      ui.host.lastFrame?.commands.compactMap { command -> String? in
        if case .text(_, let text, _, _) = command { return text }
        return nil
      } ?? []
    #expect(text.contains("Falling blocks"))
    #expect(text.contains("Start game"))
    #expect(text.contains("Chat"))
    #expect(!text.contains(where: { $0.contains("gallery") }))
  }

  @Test func boardBindingsMoveAndDropOnlyWhenBoardIsFocused() throws {
    let (state, ui) = try harness()
    state.play.start()
    ui.host.render()
    #expect(state.play.focus.isFocused)
    #expect(ui.host.resolve(KeyboardInput(chord: KeyChord("d"), text: "d")) == .command(.application("game.left")))
    let x = state.play.game.active.x
    ui.press("d")
    #expect(state.play.game.active.x == x - 1)
    ui.press(KeyboardInput(chord: KeyChord(.space), text: " "))
    #expect(state.play.game.board.compactMap { $0 }.count == 4)
    ui.press("p")
    #expect(state.play.phase == .paused)
    ui.press("p")
    #expect(state.play.phase == .playing)
    ui.press(.escape)
    #expect(state.play.phase == .paused)
    ui.press("s")
    #expect(!state.play.focus.isFocused)
    #expect(ui.host.resolve(KeyboardInput(chord: KeyChord("d"), text: "d")) == .command(.navigation(.left)))
  }

  @Test func modalKeysControlGameOnlyWhileBoardIsFocused() throws {
    let (state, ui) = try harness()
    state.play.start()
    ui.host.render()
    let x = state.play.game.active.x
    let y = state.play.game.active.y
    ui.press("d")
    #expect(state.play.game.active.x == x - 1)
    ui.press("k")
    #expect(state.play.game.active.x == x)
    ui.press("f")
    #expect(state.play.game.active.rotation == 1)
    ui.press("j")
    #expect(state.play.game.active.y == y + 1)
    #expect(state.play.game.score == 1)
    #expect(state.play.focus.isFocused)
    ui.press("s")
    #expect(!state.play.focus.isFocused)
    for (key, direction): (Character, NavigationCommand) in [
      ("d", .left), ("f", .up), ("j", .down), ("k", .right),
    ] {
      #expect(
        ui.host.resolve(KeyboardInput(chord: KeyChord(key), text: String(key))) == .command(.navigation(direction)))
    }
  }

  @Test func screenShortcutsPauseGameAndComposerKeepsNormalInput() throws {
    let (state, ui) = try harness()
    state.play.start()
    ui.host.render()
    ui.press(KeyboardInput(chord: KeyChord("2", modifiers: .command)))
    #expect(state.screen == .chat)
    #expect(state.play.phase == .paused)
    let cells = state.play.game.active.cells
    state.chat.session.input.focus(editing: true)
    ui.host.render()
    #expect(state.chat.session.input.isEditing)
    ui.press("p", "l", "a", "y")
    ui.press(KeyboardInput(chord: KeyChord(.space), text: " "))
    ui.press("d", "f", "j", "k")
    #expect(state.chat.session.draft == "play dfjk")
    #expect(ui.host.resolve(KeyboardInput(chord: KeyChord(.leftArrow))) == nil)
    ui.press(.enter)
    ui.press("h", "i")
    #expect(state.chat.session.draft == "play dfjk\nhi")
    ui.press(KeyboardInput(chord: KeyChord(.enter, modifiers: .command)))
    #expect(state.chat.session.messages[1].text == "play dfjk\nhi")
    #expect(state.chat.session.isResponding)
    #expect(state.chat.session.draft.isEmpty)
    #expect(state.play.game.active.cells == cells)
    ui.press(KeyboardInput(chord: KeyChord("1", modifiers: .command)))
    #expect(state.screen == .play)
    #expect(state.play.phase == .paused)
  }

  @Test func modalNavigationCanReachTheComposerWithoutPointerInput() throws {
    let (state, ui) = try harness()
    ui.press(KeyboardInput(chord: KeyChord("2", modifiers: .command)))
    ui.press("j", "j", "k", "l", "j", "j", "l")
    #expect(state.chat.session.input.isFocused)
    ui.press(.enter)
    #expect(state.chat.session.input.isEditing)
    ui.press("h", "i")
    ui.press(.escape)
    #expect(state.chat.session.draft == "hi")
    #expect(!state.chat.session.input.isEditing)
  }

  @Test func tabAndArrowKeysAreIgnoredInNavigationGameAndChat() throws {
    let (state, ui) = try harness()
    func expectUnboundKeys() {
      for key: Key in [.tab, .leftArrow, .rightArrow, .upArrow, .downArrow] {
        for modifiers: KeyModifiers in [[], .shift, .option, [.option, .shift]] {
          let input = KeyboardInput(chord: KeyChord(key, modifiers: modifiers), text: "\u{F700}")
          #expect(ui.host.resolve(input) == nil)
          ui.press(input)
        }
      }
    }
    expectUnboundKeys()
    state.play.start()
    ui.host.render()
    let cells = state.play.game.active.cells
    expectUnboundKeys()
    #expect(state.play.focus.isFocused)
    #expect(state.play.game.active.cells == cells)
    state.open(.chat)
    ui.host.render()
    state.chat.session.input.focus(editing: true)
    ui.host.render()
    state.chat.session.draft = "Keep this draft"
    expectUnboundKeys()
    #expect(state.chat.session.input.isEditing)
    #expect(state.chat.session.draft == "Keep this draft")
  }

  @Test func leavingBoardPausesAndReleasesGameBindings() throws {
    let (state, ui) = try harness()
    ui.press("j", "j", "l", "l")
    #expect(state.play.phase == .playing)
    #expect(state.play.focus.isFocused)
    ui.press(KeyboardInput(chord: KeyChord(.space), text: " "))
    #expect(state.play.game.score > 0)
    ui.press("s")
    #expect(state.play.phase == .paused)
    #expect(!state.play.focus.isFocused)
    #expect(ui.host.resolve(KeyboardInput(chord: KeyChord("d"), text: "d")) == .command(.navigation(.left)))
    ui.press("k", "l", "j", "l")
    #expect(state.play.phase == .playing)
    #expect(state.play.game.score == 0)
    #expect(state.play.game.board.allSatisfy { $0 == nil })
    ui.press("s", "l", "l")
    #expect(state.play.phase == .playing)
    #expect(state.play.focus.isFocused)
    ui.press("s", "f", "l", "k", "l")
    #expect(state.screen == .chat)
    #expect(state.play.phase == .paused)
  }

  @Test func chatMessagesSupportTextSelection() throws {
    let (state, ui) = try harness()
    state.open(.chat)
    let frame = ui.host.render()
    let origin = try #require(
      frame.commands.compactMap { command -> Point? in
        if case .text(let point, let text, _, _) = command, text.hasPrefix("Hey, welcome") { return point }
        return nil
      }.first)
    let target = Point(x: origin.x + 3, y: origin.y + 3)
    ui.host.render(input: InputState(pointerPosition: target, pointerDown: true, pointerPressed: true))
    ui.host.render(input: InputState(pointerPosition: target, pointerReleased: true))
    ui.press(KeyboardInput(chord: KeyChord("a", modifiers: .command)))
    #expect(
      ui.host.render().commands.contains { command in
        if case .fillRect(_, let color) = command { return color == DemoStyle.theme.focus.selectionBackground }
        return false
      })
  }

  @Test func gameControlsFitTheDefaultViewport() throws {
    let (_, ui) = try harness()
    let frame = ui.host.render()
    for case .text(let point, let text, _, let scale) in frame.commands {
      #expect(point.x >= 24 && point.y >= 24, "\(text)")
      #expect(point.y + FontMetrics().measure(text, scale: scale).height <= frame.viewport.height - 24, "\(text)")
    }
    #expect(
      !frame.commands.contains { command in
        if case .fillRect(let rect, let color) = command {
          return color == DemoStyle.theme.scrollView.indicator && rect.size.height == 3
        }
        return false
      })
    ui.host.viewport = Size(width: 800, height: 600)
    #expect(!ui.host.render().commands.isEmpty)
  }

  @Test func mouseCanStartPauseAndSwitchScreens() throws {
    let (state, ui) = try harness()
    func click(_ label: String) throws {
      let point = try #require(
        ui.host.render().commands.compactMap { command -> Point? in
          if case .text(let point, let text, _, _) = command, text == label { return point }
          return nil
        }.first)
      let target = Point(x: point.x + 2, y: point.y + 2)
      ui.host.render(input: InputState(pointerPosition: target, pointerDown: true, pointerPressed: true))
      ui.host.render(input: InputState(pointerPosition: target, pointerReleased: true))
      ui.host.render()
    }
    try click("Start game")
    #expect(state.play.phase == .playing)
    #expect(state.play.focus.isFocused)
    try click("Pause")
    #expect(state.play.phase == .paused)
    try click("Resume")
    #expect(state.play.phase == .playing)
    try click("Chat")
    #expect(state.screen == .chat)
    #expect(state.play.phase == .paused)
    try click("Build notes")
    #expect(state.chat.selectedSession == 1)
  }
}
