import Chroma
import Foundation
import HeadlessBackend
import RemoteProtocol
import Testing

@testable import DemoContent

@MainActor
struct DemoContentTests {
  @Test func animationPreservesFrameSizedTimeIncrements() {
    var now: TimeInterval = 800_000_000
    let state = PerformanceDemoState(itemCount: 100, clock: { now })
    #expect(state.elapsedTime() == 0)
    now += 1.0 / 60
    let first = state.elapsedTime()
    now += 1.0 / 60
    let second = state.elapsedTime()
    #expect(abs(first - 1.0 / 60) < 0.00001)
    #expect(abs(second - 2.0 / 60) < 0.00001)
    #expect(second > first)
  }

  @Test func animationPauseExcludesPausedTimeAndRetainsSpeed() {
    var now: TimeInterval = 800_000_000
    let state = PerformanceDemoState(itemCount: 100, clock: { now })
    now += 2
    state.togglePaused()
    #expect(state.elapsedTime() == 2)
    now += 100
    #expect(state.elapsedTime() == 2)
    state.togglePaused()
    #expect(state.elapsedTime() == 2)
    now += 0.5
    #expect(state.elapsedTime() == 2.5)
    state.speed = 2
    #expect(state.elapsedTime() == 5)
  }

  @Test func sharedSceneSurvivesWireRoundTrip() throws {
    let demo = DemoApplication(itemCount: 100, shortcutModifier: .command)
    let renderer = HeadlessRenderer(size: demo.windowSize)
    renderer.content = demo.body
    let frame = renderer.render()
    #expect(!frame.commands.isEmpty)
    var bytes = try RemoteWire.encode(
      .frame(id: 1, inputSequence: 0, viewport: frame.viewport, commands: frame.commands))
    guard case .frame(_, _, let viewport, let commands) = try RemoteWire.decode(from: &bytes) else {
      Issue.record("Expected a complete demo frame")
      return
    }
    #expect(viewport == frame.viewport)
    #expect(commands == frame.commands)
    #expect(bytes.readableBytes == 0)
  }

  @Test func shortcutsUseDisplayPlatformRatherThanDaemonPlatform() {
    let apple = DemoApplication(shortcutModifier: .command)
    let linux = DemoApplication(shortcutModifier: .superKey)
    #expect(apple.keyBindings.command(for: KeyChord("c", modifiers: .command))! == .editing(.copy))
    #expect(linux.keyBindings.command(for: KeyChord("c", modifiers: .superKey))! == .editing(.copy))
    #expect(linux.keyBindings.command(for: KeyChord("c", modifiers: .command)) == nil)
    for key: Key in [
      .character("j"), .character("f"), .character("d"), .character("k"),
      .character("l"), .character("s"), .space, .pageUp, .pageDown,
    ] {
      #expect(apple.keyBindings.command(for: KeyChord(key)) == nil)
      #expect(linux.keyBindings.command(for: KeyChord(key)) == nil)
    }
  }
}

@MainActor
@Test func captureShortcutRequestsExactlyOneFrame() throws {
  let directory = try captureTestDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let configuration = try DemoCaptureConfiguration(directory: directory)
  let demo = DemoApplication(itemCount: 100, shortcutModifier: .command, captureConfiguration: configuration)
  #expect(demo.keyBindings.command(for: KeyChord("g", modifiers: [.control, .shift]))! == .application("demo.capture"))
  let renderer = HeadlessRenderer(size: demo.windowSize)
  renderer.content = demo.body
  renderer.render()
  let requested = renderer.render(input: InputState(commands: [.application("demo.capture")]))
  #expect(
    requested.commands.contains { command in
      if case .text(_, let text, _, _) = command { return text == "Scene capture requested" }
      return false
    })
}

@MainActor
@Test func demoCaptureWritesReplayableScene() async throws {
  let directory = try captureTestDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  let configuration = try DemoCaptureConfiguration(directory: directory)
  let demo = DemoApplication(itemCount: 100, shortcutModifier: .command, captureConfiguration: configuration)
  let renderer = HeadlessRenderer(size: demo.windowSize)
  renderer.content = demo.body
  renderer.frameObserver = demo.frameObserver
  renderer.render()
  let captured = renderer.render(input: InputState(commands: [.application("demo.capture")]))
  for _ in 0..<200 {
    try await Task.sleep(for: .milliseconds(25))
    let frame = renderer.render()
    for command in frame.commands {
      if case .text(_, let text, _, _) = command, text.hasPrefix("Saved scene: ") {
        let filename = String(text.dropFirst("Saved scene: ".count))
        let url = directory.appendingPathComponent(filename)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try SceneCapture.decode(Data(contentsOf: url))
        #expect(decoded.drawList.commands == captured.commands)
        #expect(decoded.viewport == captured.viewport)
        return
      }
    }
  }
  Issue.record("Capture did not complete within five seconds")
}

private func captureTestDirectory() throws -> URL {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
  return directory
}

@MainActor
@Test func captureIsDisabledWithoutConfiguration() {
  let demo = DemoApplication()
  #expect(demo.frameObserver == nil)
  #expect(demo.keyBindings.command(for: KeyChord("g", modifiers: [.control, .shift])) == nil)
  let renderer = HeadlessRenderer(size: demo.windowSize)
  renderer.content = demo.body
  let frame = renderer.render(input: InputState(commands: [.application("demo.capture")]))
  #expect(
    !frame.commands.contains { command in
      if case .text(_, let text, _, _) = command { return text.contains("capture") }
      return false
    })
}

@Test func captureConfigurationRequiresExplicitValidDirectory() throws {
  var empty: [String] = []
  #expect(try DemoCaptureConfiguration.parse(arguments: &empty) == nil)
  for invalid in [
    ["--capture-directory"], ["--capture-directory", ""],
    ["--capture-directory", "/tmp", "--capture-directory", "/tmp"], ["--capture"],
  ] {
    var arguments = invalid
    #expect(throws: (any Error).self) { try DemoCaptureConfiguration.parse(arguments: &arguments) }
  }
  let directory = try captureTestDirectory()
  defer { try? FileManager.default.removeItem(at: directory) }
  var arguments = ["localhost", "--capture-directory", directory.path, "9328"]
  let configuration = try DemoCaptureConfiguration.parse(arguments: &arguments)
  #expect(configuration?.directory == directory.standardizedFileURL.resolvingSymlinksInPath())
  #expect(arguments == ["localhost", "9328"])
  #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  let file = directory.appendingPathComponent("not-directory")
  try Data().write(to: file)
  #expect(throws: (any Error).self) { try DemoCaptureConfiguration(directory: file) }
  #expect(throws: (any Error).self) {
    try DemoCaptureConfiguration(directory: directory.appendingPathComponent("missing"))
  }
  #expect(throws: (any Error).self) { try DemoCaptureConfiguration(directory: URL(string: "https://example.com")!) }
}

@Test func nativeCaptureDefaultUsesDemoPackageDirectory() throws {
  let expected = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .standardizedFileURL.resolvingSymlinksInPath()
  let configuration = try DemoCaptureConfiguration.nativeDefault()
  #expect(configuration.directory.path == expected.path)
  #expect(
    FileManager.default.fileExists(
      atPath: configuration.directory.appendingPathComponent("Package.swift").path))
}

@MainActor
@Test func fontTabOpensAndSurvivesWireRoundTrip() throws {
  let demo = DemoApplication(itemCount: 100, shortcutModifier: .command)
  let renderer = HeadlessRenderer(size: demo.windowSize)
  renderer.content = demo.body
  let initial = renderer.render()
  let position = try #require(
    initial.commands.compactMap { command -> Point? in
      if case .text(let point, "Font", _, _) = command { return point }
      return nil
    }.first)
  let click = Point(x: position.x + 2, y: position.y + 2)
  renderer.render(
    input: InputState(
      pointerPosition: click, pointerPressPosition: click, pointerDown: true, pointerPressed: true))
  renderer.render(
    input: InputState(
      pointerPosition: click, pointerPressPosition: click, pointerReleased: true))
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
  var bytes = try RemoteWire.encode(
    .frame(id: 2, inputSequence: 0, viewport: frame.viewport, commands: frame.commands))
  guard case .frame(_, _, _, let commands) = try RemoteWire.decode(from: &bytes) else {
    Issue.record("Expected a font demo frame")
    return
  }
  #expect(commands == frame.commands)
}

@MainActor
@Test func terminalSpecimenUsesContiguousBundledFontCells() {
  let renderer = HeadlessRenderer(size: Size(width: 500, height: 84))
  renderer.content = TerminalSpecimen()
  let rows = renderer.render().commands.compactMap { command -> Point? in
    if case .text(let position, _, _, _) = command { return position }
    return nil
  }
  #expect(rows.count == 3)
  #expect(rows.map { $0.y } == [0, 28, 56])
}

@MainActor
@Test func glyphExplorerSelectionUpdatesInspectorState() {
  let state = PerformanceDemoState(itemCount: 100)
  let renderer = HeadlessRenderer(size: Size(width: 400, height: 800))
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

extension DemoContentTests {
  @Test func animationRequestsFramesWithoutInputAndStopsWhenInactive() async throws {
    let state = PerformanceDemoState(itemCount: 100)
    let renderer = HeadlessRenderer()
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
