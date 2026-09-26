import Testing

@testable import Chroma

@MainActor
struct FocusAndCommandRegressionTests {
  @MainActor private final class Harness {
    let context = RenderContext()
    let producer = FrameProducer()

    func render(_ content: any Block, input: InputState = InputState()) {
      let isInitialFrame = context.interaction.tree == nil
      _ = producer.render(
        content: content, viewport: Size(width: 200, height: 100),
        input: input, context: context, onChange: {})
      if isInitialFrame, context.interaction.selection == nil { context.interaction.focusFirstControlForTest() }
    }
  }

  @Test func stackedRootHandlersRemainAvailableWithoutControls() {
    let harness = Harness()
    var calls: [String] = []
    let content = Text("No controls")
      .onCommand(.application("inner")) {
        calls.append("inner")
        return .handled
      }
      .padding(4)
      .onCommand(.application("outer")) {
        calls.append("outer")
        return .handled
      }
    harness.render(content)
    harness.render(content, input: InputState(commands: [.application("inner"), .application("outer")]))
    #expect(calls == ["inner", "outer"])
  }

  @Test func keyedRootHandlerRemainsAvailableWithoutControls() {
    let harness = Harness()
    var calls = 0
    let content = Text("No controls")
      .onCommand(.application("test")) {
        calls += 1
        return .handled
      }
      .id("document")
    let input = InputState(commands: [.application("test")])
    harness.render(content, input: input)
    #expect(calls == 1)
    harness.render(content, input: input)
    #expect(calls == 2)
  }

  @Test func keyedTupleChildHandlerDoesNotInterceptSibling() {
    let harness = Harness()
    var calls = 0
    // The button is the first leaf, so the keyed child's handler must not intercept for it.
    let content = BlockBuilder.buildBlock(
      Button("Sibling") {},
      Text("No controls")
        .onCommand(.application("test")) {
          calls += 1
          return .handled
        }
        .id("document"))
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == 0)
  }

  @Test func rootHandlersBubbleFromInnerToOuter() {
    let harness = Harness()
    var calls: [String] = []
    let content = Text("No controls")
      .onCommand(.application("test")) {
        calls.append("inner")
        return .ignored
      }
      .onCommand(.application("test")) {
        calls.append("outer")
        return .handled
      }
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == ["inner", "outer"])
  }

  @Test func tupleChildHandlerDoesNotInterceptSibling() {
    let harness = Harness()
    let target = FocusTarget()
    var calls = 0
    let content = BlockBuilder.buildBlock(
      Button("A") {}.onCommand(.application("test")) {
        calls += 1
        return .handled
      },
      Button("B") {}.focusTarget(target))
    target.focus()
    harness.render(content)
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == 0)
  }

  @Test func commandHandlerDoesNotInterceptSibling() {
    let harness = Harness()
    let target = FocusTarget()
    var calls: [String] = []
    let content = VStack {
      Button("A") {}.onCommand(.application("test")) {
        calls.append("A")
        return .handled
      }
      Button("B") {}.focusTarget(target).onCommand(.application("test")) {
        calls.append("B")
        return .handled
      }
    }
    target.focus()
    harness.render(content)
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == ["B"])
  }

  @Test func prunedCommandScopeDoesNotInterceptSibling() {
    let harness = Harness()
    var calls = 0
    let content = VStack {
      EmptyBlock().onCommand(.application("test")) {
        calls += 1
        return .handled
      }
      Button("B") {}
    }
    harness.render(content)
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == 0)
  }

  @Test func focusRecoversAfterEmptyTree() {
    let harness = Harness()
    var calls = 0
    let replacement = Button("After") { calls += 1 }
    harness.render(Button("Before") {})
    harness.render(EmptyBlock())
    #expect(harness.context.interaction.selection == nil)
    harness.render(replacement)
    harness.render(replacement, input: InputState(commands: [.navigation(.down), .action(.activate)]))
    #expect(calls == 1)
  }

  @Test func focusRecoversWhenReplacementPathEndsAtGroup() {
    let harness = Harness()
    var calls = 0
    harness.render(Button("Before") {})
    let replacement = VStack { Button("After") { calls += 1 } }
    harness.render(replacement)
    harness.render(replacement, input: InputState(commands: [.navigation(.down), .action(.activate)]))
    #expect(calls == 1)
  }

  @Test func navigationMovesOnlyBetweenInteractiveLeaves() {
    let harness = Harness()
    var activations = 0
    let content = VStack {
      HStack {
        Button("First") { activations += 1 }
        Button("Second") { activations += 1 }
      }
      Button("Third") { activations += 1 }
    }

    harness.render(content)
    #expect(harness.context.interaction.selection == [0, 0, 0])

    harness.render(content, input: InputState(commands: [.navigation(.down)]))
    #expect(harness.context.interaction.selection == [0, 1])
    #expect(harness.context.interaction.selectedLeafID != nil)

    harness.render(content, input: InputState(commands: [.action(.activate)]))
    #expect(activations == 1)

  }

  @Test func directionalNavigationFollowsStackStructure() {
    let harness = Harness()
    let first = FocusTarget()
    let second = FocusTarget()
    let third = FocusTarget()
    let fourth = FocusTarget()
    let content = VStack {
      HStack {
        Button("First") {}.focusTarget(first)
        Button("Second") {}.focusTarget(second)
      }
      HStack {
        Button("Third") {}.focusTarget(third)
        Button("Fourth") {}.focusTarget(fourth)
      }
    }

    second.focus()
    harness.render(content)
    #expect(harness.context.interaction.selectedLeafID == second.boundID)

    harness.render(content, input: InputState(commands: [.navigation(.down)]))
    #expect(harness.context.interaction.selectedLeafID == fourth.boundID)

    harness.render(content, input: InputState(commands: [.navigation(.left)]))
    #expect(harness.context.interaction.selectedLeafID == third.boundID)

    harness.render(content, input: InputState(commands: [.navigation(.up)]))
    #expect(harness.context.interaction.selectedLeafID == first.boundID)
  }

  @Test func customFocusGroupsNavigateAsAGrid() {
    let harness = Harness()
    let content = GridProbe(rows: 3, columns: 3)

    harness.render(content)
    #expect(harness.context.interaction.selection == [0, 0, 0])

    harness.render(content, input: InputState(commands: [.navigation(.down)]))
    #expect(harness.context.interaction.selection == [0, 1, 0])

    harness.render(content, input: InputState(commands: [.navigation(.right)]))
    #expect(harness.context.interaction.selection == [0, 1, 1])

    harness.render(content, input: InputState(commands: [.navigation(.up)]))
    #expect(harness.context.interaction.selection == [0, 0, 1])

    harness.render(content, input: InputState(commands: [.navigation(.left)]))
    #expect(harness.context.interaction.selection == [0, 0, 0])
  }

  @Test func virtualizedRowsWithoutControlsStayReachable() {
    let harness = Harness()
    let controller = ScrollViewController()
    let listID = WidgetID("plain-row-list")
    let content = LazyVStack(id: listID, data: 0..<20, rowHeight: 25, controller: controller) { index in
      Text("Row \(index)")
    }

    harness.render(content)
    let firstRow = harness.context.interaction.selectedLeafID
    #expect(firstRow != nil)

    for _ in 0..<4 {
      harness.render(content, input: InputState(commands: [.navigation(.down)]))
    }
    #expect(harness.context.interaction.scrollOffset(for: listID) == 25)
    #expect(harness.context.interaction.selectedLeafID != firstRow)

    for _ in 0..<4 {
      harness.render(content, input: InputState(commands: [.navigation(.up)]))
    }
    #expect(harness.context.interaction.selectedLeafID == firstRow)
    #expect(harness.context.interaction.scrollOffset(for: listID) == 0)
  }

  @Test func editingBlocksStructuralNavigation() {
    let harness = Harness()
    let first = FocusTarget()
    let content = VStack {
      Button("First") {}.focusTarget(first)
      Button("Second") {}
    }

    harness.render(content)
    harness.context.interaction.mode = .editing
    harness.render(content, input: InputState(commands: [.navigation(.down)]))
    #expect(harness.context.interaction.selectedLeafID == first.boundID)
  }

  @Test func defaultActionUsesTheFocusedScope() {
    let harness = Harness()
    let left = FocusTarget()
    var leftCalls = 0
    var rightCalls = 0
    let content = HStack {
      VStack {
        Button("Left control") {}.focusTarget(left)
        Button("Left default", role: .defaultAction) { leftCalls += 1 }
      }
      VStack {
        Button("Right control") {}
        Button("Right default", role: .defaultAction) { rightCalls += 1 }
      }
    }

    harness.render(content)
    left.focus()
    harness.render(content)
    harness.render(content, input: InputState(commands: [.action(.submit)]))

    #expect(leftCalls == 1)
    #expect(rightCalls == 0)
  }

  @Test func cancelLeavesEditingWhenTheFocusedScopeHasNoCancelAction() {
    let harness = Harness()
    harness.render(TextField(text: { "text" }, onChange: { _ in }))
    harness.context.interaction.beginEditing(harness.context.interaction.selectedLeafID!, caretOffset: 0)

    harness.render(TextField(text: { "text" }, onChange: { _ in }), input: InputState(commands: [.action(.cancel)]))

    #expect(harness.context.interaction.mode == .movement)
  }

  @Test func focusedBindingWinsWithoutRetryingAppBindingsAfterCommandHandling() {
    let harness = Harness()
    let target = FocusTarget()
    var appCalls = 0
    let content = Button("Control") {}.focusTarget(target)
      .keyBindings { bind("x", to: .application("local")) }
      .onCommand(.application("local")) { .ignored }
      .onCommand(.application("app")) {
        appCalls += 1
        return .handled
      }
    let appBindings = KeyBindings { bind("x", to: .application("app")) }

    target.focus()
    harness.render(content)
    #expect(
      harness.context.interaction.resolve(KeyboardInput(chord: KeyChord("x")), appBindings: appBindings)
        == .command(.application("local")))
    harness.render(content, input: InputState(commands: [.application("local")]))

    #expect(appCalls == 0)
  }

  @Test func innermostFocusedBindingWins() {
    let harness = Harness()
    let target = FocusTarget()
    let content = Button("Control") {}.focusTarget(target)
      .keyBindings { bind("x", to: .application("inner")) }
      .keyBindings { bind("x", to: .application("outer")) }

    target.focus()
    harness.render(content)

    #expect(
      harness.context.interaction.resolve(
        KeyboardInput(chord: KeyChord("x")),
        appBindings: KeyBindings { bind("x", to: .application("app")) })
        == .command(.application("inner")))
  }

  @Test func scopedBindingFollowsRestoredFocus() {
    let harness = Harness()
    let target = FocusTarget()
    let bindings = KeyBindings { bind("x", to: .application("local")) }
    let control = Button("Control") {}.focusTarget(target).keyBindings(bindings)

    target.focus()
    harness.render(control)
    harness.render(
      VStack {
        control
        Text("Added")
      })

    #expect(harness.context.interaction.selectedLeafID == target.boundID)
    #expect(
      harness.context.interaction.resolve(
        KeyboardInput(chord: KeyChord("x")), appBindings: KeyBindings())
        == .command(.application("local")))
  }

  @Test func keyboardOnlyFlowNavigatesVirtualizedRowsAndRestoresFocus() {
    let harness = Harness()
    let controller = ScrollViewController()
    let listID = WidgetID("keyboard-flow-list")
    let field = FocusTarget()
    let fallback = FocusTarget()
    let panel = FocusTarget()
    let rows = (0..<40).map { _ in FocusTarget() }
    var text = ""
    var fieldIsPresent = true
    var panelIsOpen = false
    var customShortcutCalls = 0
    let bindings = KeyBindings.vimNavigation.overlay {
      bind("x", modifiers: .control, to: .application("custom"))
      bind("o", modifiers: .control, to: .application("open-panel"))
    }

    func content() -> any Block {
      VStack {
        LazyVStack(id: listID, data: 0...40, rowHeight: 20, controller: controller) { index in
          if index < rows.count {
            Button("Row \(index)") {}.focusTarget(rows[index])
          } else if fieldIsPresent {
            TextField(text: { text }, onChange: { text = $0 }).focusTarget(field)
          } else {
            Button("Fallback") {}.focusTarget(fallback)
          }
        }
        if panelIsOpen { Button("Panel") {}.focusTarget(panel) }
      }
      .onCommand(.application("custom")) {
        customShortcutCalls += 1
        return .handled
      }
      .onCommand(.application("open-panel")) {
        panelIsOpen = true
        panel.focus()
        return .handled
      }
      .onCommand(.action(.cancel)) {
        guard panelIsOpen else { return .ignored }
        panelIsOpen = false
        if fieldIsPresent {
          field.focus()
        } else {
          fallback.focus()
        }
        return .handled
      }
    }

    func press(_ input: KeyboardInput) {
      guard let resolved = harness.context.interaction.resolve(input, appBindings: bindings) else { return }
      switch resolved {
      case .command(let command):
        harness.render(content(), input: InputState(commands: [command]))
        harness.render(content())
      case .text(let event): harness.render(content(), input: InputState(textEvents: [event]))
      }
    }

    harness.render(content())
    #expect(rows[0].isFocused)
    for _ in 0..<15 { press(KeyboardInput(chord: KeyChord(.downArrow))) }
    #expect(rows[15].isFocused)
    #expect(harness.context.interaction.scrollOffset(for: listID) > 0)
    for _ in 0..<15 { press(KeyboardInput(chord: KeyChord(.upArrow))) }
    #expect(rows[0].isFocused)
    #expect(harness.context.interaction.scrollOffset(for: listID) == 0)

    for _ in 0..<40 { press(KeyboardInput(chord: KeyChord(.downArrow))) }
    #expect(field.isFocused)
    press(KeyboardInput(chord: KeyChord(.enter)))
    #expect(field.isEditing)
    press(KeyboardInput(chord: KeyChord(.space), text: " "))
    press(KeyboardInput(chord: KeyChord(.space), text: " "))
    #expect(text == "  ")

    press(KeyboardInput(chord: KeyChord("x", modifiers: .control), text: "x"))
    #expect(customShortcutCalls == 1)
    press(KeyboardInput(chord: KeyChord(.escape)))
    #expect(field.isFocused && !field.isEditing)

    press(KeyboardInput(chord: KeyChord("o", modifiers: .control), text: "o"))
    #expect(panelIsOpen && panel.isFocused)
    press(KeyboardInput(chord: KeyChord(.escape)))
    #expect(!panelIsOpen && field.isFocused)

    press(KeyboardInput(chord: KeyChord("o", modifiers: .control), text: "o"))
    #expect(panelIsOpen && panel.isFocused)
    fieldIsPresent = false
    press(KeyboardInput(chord: KeyChord(.escape)))
    #expect(!panelIsOpen && fallback.isFocused)
  }

  @Test func scopedResolutionPreservesTextEditingShortcutRules() {
    func resolve(
      _ input: KeyboardInput,
      scoped: KeyBindings = KeyBindings(),
      app: KeyBindings = KeyBindings()
    ) -> ResolvedKeyboardInput? {
      let harness = Harness()
      let target = FocusTarget()
      let field = TextField(text: { "" }, onChange: { _ in })
        .focusTarget(target)
        .keyBindings(scoped)
      target.focus(editing: true)
      harness.render(field)
      return harness.context.interaction.resolve(input, appBindings: app)
    }

    #expect(
      resolve(
        KeyboardInput(chord: KeyChord("x", modifiers: .control), text: "x"),
        app: KeyBindings { bind("x", modifiers: .control, to: .application("cut")) })
        == .command(.application("cut")))
    #expect(
      resolve(
        KeyboardInput(chord: KeyChord("x"), text: "x"),
        scoped: KeyBindings { bind("x", in: .editing, to: .application("local")) })
        == .command(.application("local")))
    #expect(
      resolve(
        KeyboardInput(chord: KeyChord("x"), text: "x"),
        scoped: KeyBindings { disable("x", in: .editing) })
        == nil)
    #expect(resolve(KeyboardInput(chord: KeyChord("x"), text: "x")) == .text(.insert("x")))
    #expect(
      resolve(
        KeyboardInput(chord: KeyChord("x"), text: "x"),
        scoped: KeyBindings { bind("x", in: .editing, to: .application("scoped")) },
        app: KeyBindings { bind("x", in: .editing, to: .application("app")) })
        == .command(.application("scoped")))
  }
}

/// Draws a `rows` x `columns` grid of controls using only public container APIs.
private struct GridProbe: PrimitiveBlock {
  let rows: Int
  let columns: Int
  private let cell: Float = 20

  var focusRule: FocusRule { .container }

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    Size(width: Float(columns) * cell, height: Float(rows) * cell)
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    context.withFocusGroup(in: rect, axis: .vertical) {
      for row in 0..<rows {
        let rowRect = Rect(
          x: rect.minX, y: rect.minY + Float(row) * cell, width: rect.size.width, height: cell)
        context.withFocusGroup(in: rowRect, axis: .horizontal) {
          for column in 0..<columns {
            let box = Rect(
              x: rowRect.minX + Float(column) * cell, y: rowRect.minY, width: cell, height: cell)
            _ = context.childScope(row * columns + column).buttonState(in: box) {}
          }
        }
      }
    }
  }
}
