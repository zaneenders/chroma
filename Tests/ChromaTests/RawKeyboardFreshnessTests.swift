import Testing

@testable import Chroma

@MainActor
struct RawKeyboardFreshnessTests {
  private let viewport = Size(width: 200, height: 100)
  private let key = KeyboardInput(chord: KeyChord("x"), text: "x")

  private func send(_ key: KeyboardInput, to runtime: WindowRuntime) {
    runtime.handleKeyboardInput(key) { [weak runtime] resolved in
      switch resolved {
      case .command(let command): runtime?.handleInput(InputState(commands: [command]))
      case .text(let event): runtime?.handleInput(InputState(textEvents: [event]))
      }
    }
  }

  @Test func standaloneResolutionRefreshesUnobservedScopedBindings() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    var command = Command.application("old")
    runtime.setContent(
      DeferredBlock {
        Button("Target") {}.keyBindings(KeyBindings { bind("x", to: command) })
      })
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    #expect(runtime.resolve(key) == .command(.application("old")))
    command = .application("new")
    #expect(runtime.resolve(key) == .command(.application("new")))
  }

  @Test func coalescedNativeKeysRefreshBindingsExactlyOncePerEventWithoutPainting() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    var command = Command.application("old")
    var builds = 0
    var events: [String] = []
    runtime.setContent(
      DeferredBlock {
        builds += 1
        return Button("Target") {}
          .keyBindings(KeyBindings { bind("x", to: command) })
          .onCommand(.application("old")) {
            events.append("old")
            command = .application("new")
            return .handled
          }
          .onCommand(.application("new")) {
            events.append("new")
            return .handled
          }
      })
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    builds = 0
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    send(key, to: runtime)
    send(key, to: runtime)
    #expect(events == ["old", "new"])
    #expect(builds == 2)
    #expect(PipelineMetrics.snapshot.paints == 0)
  }

  @Test func pendingEditingFocusIsResolvedBeforeTheFirstCharacter() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let focus = FocusTarget()
    var text = ""
    runtime.setContent(TextEditor(text: { text }, onChange: { text = $0 }).focusTarget(focus))
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    let session = runtime.interaction.editingSessionGeneration
    focus.focus(editing: true)
    send(key, to: runtime)
    #expect(text == "x")
    #expect(runtime.interaction.editingSessionGeneration > session)
  }

  @Test func rawAndResolvedInputBeforeInitialFrameKeepTheirOrder() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let focus = FocusTarget()
    var text = ""
    runtime.setContent(TextEditor(text: { text }, onChange: { text = $0 }).focusTarget(focus))
    focus.focus(editing: true)
    runtime.handleInput(InputState(textEvents: [.insert("a")]))
    send(KeyboardInput(chord: KeyChord("b"), text: "b"), to: runtime)
    runtime.handleInput(InputState(textEvents: [.insert("c")]))
    send(KeyboardInput(chord: KeyChord("d"), text: "d"), to: runtime)
    #expect(runtime.interaction.tree == nil)
    #expect(text.isEmpty)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(text == "abcd")
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(text == "abcd")
  }

  @Test func rootReplacementDuringInitialDrainPreservesQueuedAndReentrantKeys() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let focus = FocusTarget()
    var text = ""
    var replacements = 0
    runtime.setContent(
      Text("Old root").onCommand(.application("replace")) { [weak runtime] in
        guard let runtime else { return .ignored }
        replacements += 1
        runtime.setContent(TextEditor(text: { text }, onChange: { text = $0 }).focusTarget(focus))
        focus.focus(editing: true)
        send(KeyboardInput(chord: KeyChord("c"), text: "c"), to: runtime)
        return .handled
      })
    runtime.handleInput(InputState(commands: [.application("replace")]))
    send(KeyboardInput(chord: KeyChord("b"), text: "b"), to: runtime)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(replacements == 1)
    #expect(text == "bc")
  }

  @Test func standaloneResolutionCannotReusePreparationAcrossAnUnobservedMutation() throws {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    var value = 0
    runtime.setContent(
      DeferredBlock {
        let captured = value
        return Button("Target") { value = captured + 1 }
          .keyBindings(KeyBindings { bind("x", to: .action(.activate)) })
      })
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    let resolved = try #require(runtime.resolve(key))
    value = 10
    if case .command(let command) = resolved { runtime.handleInput(InputState(commands: [command])) }
    #expect(value == 11)
  }

  @Test func clipboardTranslationSeesTheLastRealPointerPosition() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    runtime.setContent(Text("Target"))
    runtime.keyBindings = KeyBindings { bind("x", to: .editing(.selectAll)) }
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    let point = Point(x: 45, y: 32)
    runtime.handleInput(InputState(pointerPosition: point))
    runtime.handleKeyboardInput(key) { resolved in
      #expect(resolved == .text(.selectAll))
      #expect(runtime.interaction.input.pointerPosition == point)
      runtime.handleInput(InputState(pointerPosition: point))
    }
  }

  @Test func rawNavigationPreparesTheAdjacentVirtualRowInOneUpdate() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let controller = ScrollViewController()
    let targets = (0..<10).map { _ in FocusTarget() }
    var built: [Int] = []
    runtime.setContent(
      ScrollView(data: 0..<10, rowHeight: 30, controller: controller) { index in
        built.append(index)
        return Button("Row \(index)") {}.focusTarget(targets[index])
      })
    runtime.keyBindings = KeyBindings { bind("x", to: .navigation(.down)) }
    _ = runtime.render(viewport: Size(width: 100, height: 20), input: InputState(), onChange: {})
    let point = Point(x: 5, y: 5)
    runtime.handleInput(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    runtime.handleInput(InputState(pointerPosition: point, pointerReleased: true))
    #expect(targets[0].isFocused)
    built = []
    send(key, to: runtime)
    #expect(targets[1].isFocused)
    #expect(built == [0, 1])
  }

  @Test func ignoredRawKeyLeavesTheWindowIdle() throws {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    runtime.setContent(Text("Static").padding(20))
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.handleInput(InputState(pointerPosition: Point(x: 45, y: 32)))
    let hovered = try #require(runtime.interaction.hoveredLeafID)
    runtime.scheduler.consumeContentRequest()
    _ = runtime.interaction.consumeRedrawRequest()
    #expect(runtime.scheduler.nextFrame == nil)
    var deliveries = 0
    runtime.handleKeyboardInput(key) { _ in deliveries += 1 }
    #expect(deliveries == 0)
    #expect(runtime.interaction.hoveredLeafID == hovered)
    #expect(runtime.scheduler.nextFrame == nil)
  }
}
