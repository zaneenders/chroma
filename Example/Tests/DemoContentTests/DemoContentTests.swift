import Chroma
import Foundation
import ChromaTesting
import Synchronization
import Testing

@testable import DemoContent

@MainActor
struct DemoContentTests {
  @Test func animationPreservesFrameSizedTimeIncrements() {
    let now = Mutex<TimeInterval>(800_000_000)
    let state = PerformanceDemoState(itemCount: 100, clock: { now.withLock { $0 } })
    #expect(state.elapsedTime() == 0)
    now.withLock { $0 += 1.0 / 60 }
    let first = state.elapsedTime()
    now.withLock { $0 += 1.0 / 60 }
    let second = state.elapsedTime()
    #expect(abs(first - 1.0 / 60) < 0.00001)
    #expect(abs(second - 2.0 / 60) < 0.00001)
    #expect(second > first)
  }

  @Test func animationPauseExcludesPausedTimeAndRetainsSpeed() {
    let now = Mutex<TimeInterval>(800_000_000)
    let state = PerformanceDemoState(itemCount: 100, clock: { now.withLock { $0 } })
    now.withLock { $0 += 2 }
    state.togglePaused()
    #expect(state.elapsedTime() == 2)
    now.withLock { $0 += 100 }
    #expect(state.elapsedTime() == 2)
    state.togglePaused()
    #expect(state.elapsedTime() == 2)
    now.withLock { $0 += 0.5 }
    #expect(state.elapsedTime() == 2.5)
    state.speed = 2
    #expect(state.elapsedTime() == 5)
  }

  @Test func defaultClipboardShortcutsUsePlatformModifier() {
    let demo = DemoApplication()
    #if os(macOS)
    let modifier: KeyModifiers = .command
    #else
    let modifier: KeyModifiers = .control
    #endif
    for (key, event): (Character, TextEditEvent) in [
      ("a", .selectAll), ("c", .copy), ("x", .cut), ("v", .paste),
    ] {
      #expect(demo.keyBindings.command(for: KeyChord(key, modifiers: modifier))! == .editing(event))
    }
  }

  #if os(Linux)
  @Test func linuxClipboardShortcutsSupportControlAndSuper() {
    for demo in [DemoApplication(), DemoApplication(shortcutModifier: .superKey)] {
      for modifier: KeyModifiers in [.control, .superKey] {
        for (key, event): (Character, TextEditEvent) in [
          ("a", .selectAll), ("c", .copy), ("x", .cut), ("v", .paste),
        ] {
          #expect(demo.keyBindings.command(for: KeyChord(key, modifiers: modifier))! == .editing(event))
        }
      }
    }
  }
  #endif

  @Test func shortcutsUseConfiguredPlatform() {
    let apple = DemoApplication(shortcutModifier: .command)
    let linux = DemoApplication(shortcutModifier: .superKey)
    #expect(apple.keyBindings.command(for: KeyChord("c", modifiers: .command))! == .editing(.copy))
    #expect(linux.keyBindings.command(for: KeyChord("c", modifiers: .superKey))! == .editing(.copy))
    #expect(linux.keyBindings.command(for: KeyChord("c", modifiers: .command)) == nil)
    for (key, command) in [
      (Key.character("s"), NavigationCommand.stepOut),
      (Key.character("l"), NavigationCommand.stepIn),
    ] {
      #expect(apple.keyBindings.command(for: KeyChord(key))! == .navigation(command))
      #expect(linux.keyBindings.command(for: KeyChord(key))! == .navigation(command))
      #expect(apple.keyBindings.command(for: KeyChord(key), isTextEditing: true) == nil)
      #expect(linux.keyBindings.command(for: KeyChord(key), isTextEditing: true) == nil)
    }
    for key: Key in [.pageUp, .pageDown] {
      #expect(apple.keyBindings.command(for: KeyChord(key)) == nil)
      #expect(linux.keyBindings.command(for: KeyChord(key)) == nil)
    }
  }
}

@MainActor
private func clickFontTab(_ renderer: HeadlessHost) throws {
  let initial = renderer.render()
  let tab = try #require(
    initial.commands.compactMap { command -> Point? in
      if case .text(let point, "Font", _, _) = command { return point }
      return nil
    }.first)
  let click = Point(x: tab.x + 2, y: tab.y + 2)
  renderer.render(
    input: InputState(
      pointerPosition: click, pointerPressPosition: click, pointerDown: true, pointerPressed: true))
  renderer.render(
    input: InputState(
      pointerPosition: click, pointerPressPosition: click, pointerReleased: true))
}

@MainActor
private func focusedGlyphCell(_ renderer: HeadlessHost) -> Rect? {
  let frame = renderer.render(input: InputState(pointerPosition: Point(x: 5000, y: 5000)))
  for command in frame.commands {
    if case .fillRect(let rect, let color) = command,
      color == HoverStyle.standardTint(in: .dark),
      rect.size.width == 40, rect.size.height == 40
    {
      return rect
    }
  }
  return nil
}

@MainActor
@Test func fontTabOpensAndRendersSample() throws {
  let demo = DemoApplication(itemCount: 100, shortcutModifier: .command)
  let renderer = HeadlessHost(size: demo.windowSize)
  let gallery = PerformanceDemoState(itemCount: 100)
  renderer.content = DeferredBlock { PerformanceDemo(state: gallery) }
  try clickFontTab(renderer)
  let frame = renderer.render()
  #expect(
    frame.commands.contains { command in
      if case .text(_, "BUNDLED MONOSPACE FONT", _, _) = command { return true }
      return false
    })
  #expect(
    frame.commands.contains { command in
      if case .text(_, "café Ångström naïve façade Český", _, _) = command { return true }
      return false
    })

}

@MainActor
@Test func terminalSpecimenUsesContiguousBundledFontCells() {
  let renderer = HeadlessHost(size: Size(width: 500, height: 84))
  renderer.content = TerminalSpecimen()
  let rows = renderer.render().commands.compactMap { command -> Point? in
    if case .text(let position, _, _, _) = command { return position }
    return nil
  }
  #expect(rows.count == 3)
  #expect(rows.map { $0.y } == [0, 28, 56])
}

@MainActor
@Test func fontPageArrowKeysMoveTheGlyphHighlight() throws {
  let demo = DemoApplication(itemCount: 100, shortcutModifier: .command)
  let renderer = HeadlessHost(size: demo.windowSize)
  let gallery = PerformanceDemoState(itemCount: 100)
  renderer.content = DeferredBlock { PerformanceDemo(state: gallery) }
  try clickFontTab(renderer)

  func highlightedCell() -> Point? {
    let frame = renderer.render()
    var accent: Color?
    for case .text(_, "BUNDLED MONOSPACE FONT", let color, _) in frame.commands { accent = color }
    guard let accent else { return nil }
    for case .text(let position, let text, let color, _) in frame.commands
    where text.count == 1 && color == accent { return position }
    return nil
  }

  func press(_ command: Command) {
    renderer.render(input: InputState(commands: [command]))
  }
  func activateCell() throws -> Point {
    press(.action(.activate))
    return try #require(highlightedCell())
  }

  renderer.render(input: InputState(commands: [.navigation(.down), .navigation(.stepIn)]))
  let initialHighlight = try #require(highlightedCell())
  let cell: Float = 40
  for _ in 0..<50 {
    press(.navigation(.down))
    if focusedGlyphCell(renderer) != nil { break }
  }
  let firstRow = try activateCell()
  press(.navigation(.down))
  let secondRow = try activateCell()
  #expect(secondRow.x == firstRow.x)
  #expect(secondRow.y == firstRow.y + cell)
  press(.navigation(.right))
  let secondRowNextColumn = try activateCell()
  #expect(secondRowNextColumn.x == secondRow.x + cell)
  #expect(secondRowNextColumn.y == secondRow.y)
  press(.navigation(.up))
  let firstRowNextColumn = try activateCell()
  #expect(firstRowNextColumn.x == firstRow.x + cell)
  #expect(firstRowNextColumn.y == firstRow.y)
  #expect(initialHighlight != firstRow)
}

@MainActor
@Test func escapeLeavesTheFontPreviewField() throws {
  let demo = DemoApplication(itemCount: 100, shortcutModifier: .command)
  let renderer = HeadlessHost(size: demo.windowSize)
  let gallery = PerformanceDemoState(itemCount: 100)
  renderer.content = DeferredBlock { PerformanceDemo(state: gallery) }
  try clickFontTab(renderer)

  func highlightedCell() -> Point? {
    let frame = renderer.render()
    var accent: Color?
    for case .text(_, "BUNDLED MONOSPACE FONT", let color, _) in frame.commands { accent = color }
    guard let accent else { return nil }
    for case .text(let position, let text, let color, _) in frame.commands
    where text.count == 1 && color == accent { return position }
    return nil
  }
  func press(_ command: Command) {
    renderer.render(input: InputState(commands: [command]))
  }
  func activate() -> Point? {
    press(.action(.activate))
    return highlightedCell()
  }

  let preview = try #require(
    renderer.render().commands.compactMap { command -> Point? in
      if case .text(let point, "LIVE PREVIEW", _, _) = command { return point }
      return nil
    }.first)
  let click = Point(x: preview.x + 15, y: preview.y + 35)
  renderer.render(
    input: InputState(pointerPosition: click, pointerPressPosition: click, pointerDown: true, pointerPressed: true))
  renderer.render(input: InputState(pointerPosition: click, pointerPressPosition: click, pointerReleased: true))
  let before = try #require(highlightedCell())
  press(.navigation(.down))
  press(.action(.activate))
  press(.navigation(.down))
  press(.navigation(.down))
  #expect(activate() == before)

  renderer.render(input: InputState(textEvents: [.endEditing]))
  press(.navigation(.stepOut))
  for _ in 0..<50 {
    press(.navigation(.down))
    if focusedGlyphCell(renderer) != nil { break }
  }
  #expect(activate() != before)
}

@MainActor
@Test func glyphExplorerSelectionUpdatesInspectorState() {
  let state = PerformanceDemoState(itemCount: 100)
  let renderer = HeadlessHost(size: Size(width: 400, height: 800))
  renderer.content = GlyphExplorer(state: state)
  renderer.render()
  let point = Point(x: 20, y: 20)
  renderer.render(
    input: InputState(
      pointerPosition: point, pointerPressPosition: point,
      pointerDown: true, pointerPressed: true))
  renderer.render(
    input: InputState(
      pointerPosition: point, pointerPressPosition: point,
      pointerReleased: true))
  #expect(state.inspectedGlyph == "A")
  let frame = renderer.render()
  #expect(
    frame.commands.contains { command in
      if case .text(_, "A", _, _) = command { return true }
      return false
    })
}

@MainActor
@Test func glyphExplorerCellsHighlightHoverAndFocus() {
  let state = PerformanceDemoState(itemCount: 100)
  let renderer = HeadlessHost(size: Size(width: 400, height: 800))
  renderer.content = GlyphExplorer(state: state)
  let tint = HoverStyle.standardTint(in: .dark)
  let pressedTint = HoverStyle.standardTint(in: .dark, pressed: true)
  let parked = InputState(pointerPosition: Point(x: 5000, y: 5000))

  func tintRects() -> [Rect] {
    renderer.render(input: parked).commands.compactMap { command -> Rect? in
      if case .fillRect(let rect, let color) = command, color == tint { return rect }
      return nil
    }
  }

  renderer.render(input: parked)
  renderer.render(input: InputState(commands: [.navigation(.down)]))
  #expect(tintRects() == [Rect(x: 0, y: 0, width: 40, height: 40)])

  let hovered = renderer.render(input: InputState(pointerPosition: Point(x: 45, y: 85)))
  #expect(
    hovered.commands.contains { command in
      if case .fillRect(let rect, let color) = command {
        return rect == Rect(x: 40, y: 80, width: 40, height: 40) && color == tint
      }
      return false
    })

  let pressed = renderer.render(
    input: InputState(
      pointerPosition: Point(x: 45, y: 85), pointerDown: true, pointerPressed: true))
  #expect(
    pressed.commands.contains { command in
      if case .fillRect(let rect, let color) = command {
        return rect == Rect(x: 40, y: 80, width: 40, height: 40) && color == pressedTint
      }
      return false
    })
}

extension DemoContentTests {
  @Test func scenePageScrollsTheUuidListWithArrowKeys() throws {
    let demo = DemoApplication(itemCount: 100, shortcutModifier: .command)
    let renderer = HeadlessHost(size: demo.windowSize)
    let gallery = PerformanceDemoState(itemCount: 100)
    renderer.content = DeferredBlock { PerformanceDemo(state: gallery) }

    func firstVisibleRow() -> Int? {
      renderer.render().commands.compactMap { command -> Int? in
        guard case .text(_, let text, _, _) = command, text.hasPrefix("UUID ") else { return nil }
        return Int(text.dropFirst("UUID ".count))
      }.min()
    }

    let header = try #require(
      renderer.render().commands.compactMap { command -> Point? in
        if case .text(let point, let text, _, _) = command, text == "UUID 1" {
          return point
        }
        return nil
      }.first)
    let click = Point(x: header.x + 2, y: header.y + 2)
    renderer.render(
      input: InputState(
        pointerPosition: click, pointerPressPosition: click, pointerDown: true, pointerPressed: true))
    renderer.render(
      input: InputState(pointerPosition: click, pointerPressPosition: click, pointerReleased: true))

    #expect(firstVisibleRow() == 1)
    for _ in 0..<200 {
      renderer.render(input: InputState(commands: [.navigation(.down)]))
      if let row = firstVisibleRow(), row > 1 { break }
    }
    #expect((firstVisibleRow() ?? 0) > 1)
  }

  @Test func scenePageStepsOutOfTheUuidListAndBackToTheRememberedRow() throws {
    let demo = DemoApplication(itemCount: 100, shortcutModifier: .command)
    let renderer = HeadlessHost(size: demo.windowSize)
    let gallery = PerformanceDemoState(itemCount: 100)
    renderer.content = DeferredBlock { PerformanceDemo(state: gallery) }
    let parked = InputState(pointerPosition: Point(x: 5000, y: 5000))

    func firstVisibleRow() -> Int? {
      renderer.render(input: parked).commands.compactMap { command -> Int? in
        guard case .text(_, let text, _, _) = command, text.hasPrefix("UUID ") else { return nil }
        return Int(text.dropFirst("UUID ".count))
      }.min()
    }

    func tintRects() -> [Rect] {
      renderer.render(input: parked).commands.compactMap { command -> Rect? in
        if case .fillRect(let rect, let color) = command, color == HoverStyle.standardTint(in: .dark) {
          return rect
        }
        return nil
      }
    }

    func uuidTextOrigins() -> [Point] {
      renderer.render(input: parked).commands.compactMap { command -> Point? in
        guard case .text(let point, let text, _, _) = command, text.hasPrefix("UUID ") else { return nil }
        return point
      }
    }

    func focusCoversARow() -> Bool {
      let tints = tintRects()
      return uuidTextOrigins().contains { origin in tints.contains { $0.contains(origin) } }
    }

    let header = try #require(
      renderer.render().commands.compactMap { command -> Point? in
        if case .text(let point, let text, _, _) = command, text == "UUID 1" {
          return point
        }
        return nil
      }.first)
    let click = Point(x: header.x + 2, y: header.y + 2)
    renderer.render(
      input: InputState(
        pointerPosition: click, pointerPressPosition: click, pointerDown: true, pointerPressed: true))
    renderer.render(
      input: InputState(pointerPosition: click, pointerPressPosition: click, pointerReleased: true))
    #expect(firstVisibleRow() == 1)

    for _ in 0..<200 {
      renderer.render(input: InputState(commands: [.navigation(.down)]))
      if let row = firstVisibleRow(), row > 1 { break }
    }
    let deepRow = try #require(firstVisibleRow())
    #expect(deepRow > 1)
    #expect(focusCoversARow())

    renderer.render(input: InputState(commands: [.navigation(.stepOut)]))
    #expect(!focusCoversARow())

    renderer.render(input: InputState(commands: [.navigation(.stepIn)]))
    #expect(firstVisibleRow() == deepRow)
    #expect(focusCoversARow())
  }

  @Test func middleButtonRevealsVirtualizedRow() throws {
    let state = PerformanceDemoState(itemCount: 100)
    state.togglePaused()
    let host = HeadlessHost(size: Size(width: 1200, height: 820))
    host.content = DeferredBlock { PerformanceDemo(state: state) }
    let position = try #require(
      host.render().commands.compactMap { command -> Point? in
        if case .text(let position, let text, _, _) = command, text == "Middle" { return position }
        return nil
      }.first)
    let click = Point(x: position.x + 2, y: position.y + 2)
    host.render(input: InputState(pointerPosition: click, pointerDown: true, pointerPressed: true))
    host.render(input: InputState(pointerPosition: click, pointerReleased: true))
    let frame = host.render()
    #expect(state.uuidScrollController.offset == Float(state.identifiers.count / 2) * 53)
    #expect(
      frame.commands.contains {
        if case .text(_, let text, _, _) = $0 { return text == "UUID 5001" }
        return false
      })
    #expect(host.nextAnimationDeadline == nil)
  }

  @Test func animationRequestsFramesWithoutInputAndStopsWhenInactive() async throws {
    let state = PerformanceDemoState(itemCount: 100)
    let renderer = HeadlessHost()
    renderer.content = DeferredBlock { PerformanceDemo(state: state) }
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    defer { renderer.close() }

    let first = renderer.render()
    #expect(renderer.needsAnimationFrame)
    try await Task.sleep(for: .milliseconds(20))
    #expect(renderer.render() != first)

    state.togglePaused()
    renderer.render()
    redraws = 0
    try await Task.sleep(for: .milliseconds(100))
    #expect(redraws == 0)
    #expect(!renderer.needsAnimationFrame)

    state.togglePaused()
    renderer.render()
    redraws = 0
    #expect(renderer.needsAnimationFrame)
    try await Task.sleep(for: .milliseconds(20))

    state.page = .font
    renderer.render()
    redraws = 0
    try await Task.sleep(for: .milliseconds(100))
    #expect(redraws == 0)
    #expect(!renderer.needsAnimationFrame)

    state.page = .scene
    renderer.render()
    redraws = 0
    #expect(renderer.needsAnimationFrame)
    try await Task.sleep(for: .milliseconds(20))
  }

  @Test func animationStateIsReleasedWithoutATask() async throws {
    weak var released: PerformanceDemoState?
    do {
      let state = PerformanceDemoState(itemCount: 100)
      released = state
      try await Task.sleep(for: .milliseconds(30))
    }
    #expect(released == nil)
  }
}
