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
    runtime.build = { buffer, context in
      let node322 = buffer.button(Button("Target") {}, context: context)
      return buffer.keyBindings(node322, KeyBindings { bind("x", to: command) }, context: context)
    }
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
    runtime.build = { buffer, context in
      builds += 1
      let node324 = buffer.button(Button("Target") {}, context: context)
      let node325 = buffer.keyBindings(node324, KeyBindings { bind("x", to: command) }, context: context)
      let node326 = buffer.onCommand(
        node325, .application("old"), context: context,
        action: {
          events.append("old")
          command = .application("new")
          return .handled
        })
      let node327 = buffer.onCommand(
        node326, .application("new"), context: context,
        action: {
          events.append("new")
          return .handled
        })
      return node327
    }
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
    runtime.build = { buffer, context in
      let node329 = buffer.focus(
        focus, context: context,
        content: { buffer, context in
          return buffer.textEditor(TextEditor(text: { text }, onChange: { text = $0 }), context: context)
        })
      return node329
    }
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
    runtime.build = { buffer, context in
      let node331 = buffer.focus(
        focus, context: context,
        content: { buffer, context in
          return buffer.textEditor(TextEditor(text: { text }, onChange: { text = $0 }), context: context)
        })
      return node331
    }
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
    runtime.build = { buffer, context in
      let node332 = buffer.text(Text("Old root"), context: context)
      let node333 = buffer.onCommand(
        node332, .application("replace"), context: context,
        action: { [weak runtime] in
          guard let runtime else { return .ignored }
          replacements += 1
          runtime.build = { buffer, context in
            buffer.focus(focus, context: context) { buffer, context in
              buffer.textEditor(TextEditor(text: { text }, onChange: { text = $0 }), context: context)
            }
          }
          focus.focus(editing: true)
          send(KeyboardInput(chord: KeyChord("c"), text: "c"), to: runtime)
          return .handled
        })
      return node333
    }
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
    runtime.build = { buffer, context in
      let captured = value
      let node334 = buffer.button(Button("Target") { value = captured + 1 }, context: context)
      return buffer.keyBindings(node334, KeyBindings { bind("x", to: .action(.activate)) }, context: context)
    }
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
    runtime.build = { buffer, context in
      return buffer.text(Text("Target"), context: context)
    }
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
    runtime.build = { buffer, context in
      let node339 = buffer.scrollView(
        ScrollView(
          data: 0..<10, rowHeight: 30, controller: controller,
          build: { buffer, context, index in
            built.append(index)
            let node338 = buffer.focus(
              targets[index], context: context,
              content: { buffer, context in
                return buffer.button(Button("Row \(index)") {}, context: context)
              })
            return node338
          }), context: context)
      return node339
    }
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
    runtime.build = { buffer, context in
      let node340 = buffer.text(Text("Static"), context: context)
      return buffer.padding(node340, 20, context: context)
    }
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
