import Chroma
import ChromaTesting
import Testing

@testable import DemoContent

@MainActor
struct ClipboardSelectionTests {
  @Test func clipboardSourceSelectsTextWithTheDisplayedShortcuts() throws {
    let gallery = PerformanceDemoState(itemCount: 10)
    gallery.page = .clipboard
    let test = NavigationTestHost(
      content: PerformanceDemo(state: gallery), size: Size(width: 1200, height: 820),
      keyBindings: DemoApplication(shortcutModifier: .command).keyBindings)
    test.host.render()
    let source = try #require(test.host.lastFrame?.commands.compactMap { command -> Point? in
      if case .text(let point, "Copy this text — hello from Chroma!", _, _) = command { return point }
      return nil
    }.first)
    let target = Point(x: source.x + 30, y: source.y + 5)
    test.host.render(input: InputState(pointerPosition: target, pointerPressPosition: target, pointerDown: true, pointerPressed: true))
    test.host.render(input: InputState(pointerPosition: target, pointerPressPosition: target, pointerReleased: true))
    test.press(KeyboardInput(chord: KeyChord(.escape)))
    test.press(KeyboardInput(chord: KeyChord("d"), text: "d"))
    test.press(KeyboardInput(chord: KeyChord("k", modifiers: .shift), text: "K"))
    let partial = test.host.render(input: InputState(pointerPosition: Point(x: 5000, y: 5000)))
    #expect(partial.commands.contains { command in
      if case .fillRect(_, let color) = command { return color == ChromaTheme.dark.focus.selectionBackground }
      return false
    } == true)
    test.press(KeyboardInput(chord: KeyChord("a", modifiers: .command)))
    let frame = test.host.render(input: InputState(pointerPosition: Point(x: 5000, y: 5000)))
    #expect(frame.commands.contains { command in
      if case .fillRect(_, let color) = command { return color == ChromaTheme.dark.focus.selectionBackground }
      return false
    } == true)
  }
}
