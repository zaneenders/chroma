import Testing

@testable import Chroma

@MainActor
struct FocusAndCommandRegressionTests {
  @MainActor private final class Harness {
    let runtime = WindowRuntime()
    var context: LayoutContext { runtime.context }
    private var currentContent: LayoutBuilder = { buffer, context in
      buffer.empty(context: context)
    }

    init() {
      runtime.build = { [unowned self] buffer, context in
        currentContent(&buffer, context)
      }
    }

    func render(_ content: @escaping LayoutBuilder, input: InputState = InputState()) {
      let isInitialFrame = context.interaction.tree == nil
      currentContent = content
      _ = runtime.render(
        viewport: Size(width: 200, height: 100),
        input: input, onChange: {})
      if isInitialFrame, context.interaction.selection == nil { context.interaction.focusFirstControlForTest() }
    }
  }

  @Test func stackedRootHandlersRemainAvailableWithoutControls() {
    let harness = Harness()
    var calls: [String] = []
    let content: LayoutBuilder = { buffer, context in
      let node69 = buffer.text(Text("No controls"), context: context)
      let node70 = buffer.onCommand(
        node69, .application("inner"), context: context,
        action: {
          calls.append("inner")
          return .handled
        })
      let node71 = buffer.padding(node70, 4, context: context)
      let node72 = buffer.onCommand(
        node71, .application("outer"), context: context,
        action: {
          calls.append("outer")
          return .handled
        })
      return node72
    }
    harness.render(content)
    harness.render(content, input: InputState(commands: [.application("inner"), .application("outer")]))
    #expect(calls == ["inner", "outer"])
  }

  @Test func keyedRootHandlerRemainsAvailableWithoutControls() {
    let harness = Harness()
    var calls = 0
    let content: LayoutBuilder = { buffer, context in
      let node73 = buffer.text(Text("No controls"), context: context.keyed("document"))
      let node74 = buffer.onCommand(
        node73, .application("test"), context: context.keyed("document"),
        action: {
          calls += 1
          return .handled
        })
      return node74
    }
    let input = InputState(commands: [.application("test")])
    harness.render(content, input: input)
    #expect(calls == 1)
    harness.render(content, input: input)
    #expect(calls == 2)
  }

  @Test func keyedTupleChildHandlerDoesNotInterceptSibling() {
    let harness = Harness()
    var calls = 0
    let content: LayoutBuilder = { buffer, context in
      let node75 = buffer.button(Button("Sibling") {}, context: context.childScope(0))
      let node76 = buffer.text(Text("No controls"), context: context.childScope(1).keyed("document"))
      let node77 = buffer.onCommand(
        node76, .application("test"), context: context.childScope(1).keyed("document"),
        action: {
          calls += 1
          return .handled
        })
      return buffer.overlay([node75, node77], group: false, context: context)
    }
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == 0)
  }

  @Test func rootHandlersBubbleFromInnerToOuter() {
    let harness = Harness()
    var calls: [String] = []
    let content: LayoutBuilder = { buffer, context in
      let node79 = buffer.text(Text("No controls"), context: context)
      let node80 = buffer.onCommand(
        node79, .application("test"), context: context,
        action: {
          calls.append("inner")
          return .ignored
        })
      let node81 = buffer.onCommand(
        node80, .application("test"), context: context,
        action: {
          calls.append("outer")
          return .handled
        })
      return node81
    }
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == ["inner", "outer"])
  }

  @Test func tupleChildHandlerDoesNotInterceptSibling() {
    let harness = Harness()
    let target = FocusTarget()
    var calls = 0
    let content: LayoutBuilder = { buffer, context in
      let node82 = buffer.button(Button("A") {}, context: context.childScope(0))
      let node83 = buffer.onCommand(
        node82, .application("test"), context: context.childScope(0),
        action: {
          calls += 1
          return .handled
        })
      let node85 = buffer.focus(
        target, context: context.childScope(1),
        content: { buffer, context in
          return buffer.button(Button("B") {}, context: context)
        })
      return buffer.overlay([node83, node85], group: false, context: context)
    }
    target.focus()
    harness.render(content)
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == 0)
  }

  @Test func commandHandlerDoesNotInterceptSibling() {
    let harness = Harness()
    let target = FocusTarget()
    var calls: [String] = []
    let content: LayoutBuilder = { buffer, context in
      let node87 = buffer.button(Button("A") {}, context: context.childScope(0))
      let node88 = buffer.onCommand(
        node87, .application("test"), context: context.childScope(0),
        action: {
          calls.append("A")
          return .handled
        })
      let node90 = buffer.focus(
        target, context: context.childScope(1),
        content: { buffer, context in
          return buffer.button(Button("B") {}, context: context)
        })
      let node91 = buffer.onCommand(
        node90, .application("test"), context: context.childScope(1),
        action: {
          calls.append("B")
          return .handled
        })
      return buffer.stack([node88, node91], axis: .vertical, context: context)
    }
    target.focus()
    harness.render(content)
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == ["B"])
  }

  @Test func prunedCommandScopeDoesNotInterceptSibling() {
    let harness = Harness()
    var calls = 0
    let content: LayoutBuilder = { buffer, context in
      let node93 = buffer.empty(context: context.childScope(0))
      let node94 = buffer.onCommand(
        node93, .application("test"), context: context.childScope(0),
        action: {
          calls += 1
          return .handled
        })
      let node95 = buffer.button(Button("B") {}, context: context.childScope(1))
      return buffer.stack([node94, node95], axis: .vertical, context: context)
    }
    harness.render(content)
    harness.render(content, input: InputState(commands: [.application("test")]))
    #expect(calls == 0)
  }

  @Test func focusRecoversAfterEmptyTree() {
    let harness = Harness()
    var calls = 0
    let replacement: LayoutBuilder = { buffer, context in
      return buffer.button(Button("After") { calls += 1 }, context: context)
    }
    harness.render({ buffer, context in
      return buffer.button(Button("Before") {}, context: context)
    })
    harness.render({ buffer, context in
      return buffer.empty(context: context)
    })
    #expect(harness.context.interaction.selection == nil)
    harness.render(replacement)
    harness.render(replacement, input: InputState(commands: [.navigation(.down), .action(.activate)]))
    #expect(calls == 1)
  }

  @Test func focusRecoversWhenReplacementPathEndsAtGroup() {
    let harness = Harness()
    var calls = 0
    harness.render({ buffer, context in
      return buffer.button(Button("Before") {}, context: context)
    })
    let replacement: LayoutBuilder = { buffer, context in
      let node101 = buffer.button(Button("After") { calls += 1 }, context: context.childScope(0))
      return buffer.stack([node101], axis: .vertical, context: context)
    }
    harness.render(replacement)
    harness.render(replacement, input: InputState(commands: [.navigation(.down), .action(.activate)]))
    #expect(calls == 1)
  }

  @Test func navigationMovesOnlyBetweenInteractiveLeaves() {
    let harness = Harness()
    var activations = 0
    let content: LayoutBuilder = { buffer, context in
      let node103 = buffer.button(Button("First") { activations += 1 }, context: context.childScope(0).childScope(0))
      let node104 = buffer.button(Button("Second") { activations += 1 }, context: context.childScope(0).childScope(1))
      let node105 = buffer.stack([node103, node104], axis: .horizontal, context: context.childScope(0))
      let node106 = buffer.button(Button("Third") { activations += 1 }, context: context.childScope(1))
      return buffer.stack([node105, node106], axis: .vertical, context: context)
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
    let content: LayoutBuilder = { buffer, context in
      let node109 = buffer.focus(
        first, context: context.childScope(0).childScope(0),
        content: { buffer, context in
          return buffer.button(Button("First") {}, context: context)
        })
      let node111 = buffer.focus(
        second, context: context.childScope(0).childScope(1),
        content: { buffer, context in
          return buffer.button(Button("Second") {}, context: context)
        })
      let node112 = buffer.stack([node109, node111], axis: .horizontal, context: context.childScope(0))
      let node114 = buffer.focus(
        third, context: context.childScope(1).childScope(0),
        content: { buffer, context in
          return buffer.button(Button("Third") {}, context: context)
        })
      let node116 = buffer.focus(
        fourth, context: context.childScope(1).childScope(1),
        content: { buffer, context in
          return buffer.button(Button("Fourth") {}, context: context)
        })
      let node117 = buffer.stack([node114, node116], axis: .horizontal, context: context.childScope(1))
      return buffer.stack([node112, node117], axis: .vertical, context: context)
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
    let content: LayoutBuilder = { buffer, context in
      return GridProbe(rows: 3, columns: 3).build(into: &buffer, context: context)
    }

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
    let content: LayoutBuilder = { buffer, context in
      let node121 = buffer.scrollView(
        ScrollView(
          data: 0..<20, rowHeight: 25, controller: controller,
          build: { buffer, context, index in
            return buffer.text(Text("Row \(index)"), context: context)
          }), context: context.keyed(listID))
      return node121
    }

    harness.render(content)
    let firstRow = harness.context.interaction.selectedLeafID
    #expect(firstRow != nil)

    for _ in 0..<4 {
      harness.render(content, input: InputState(commands: [.navigation(.down)]))
    }
    #expect(harness.context.interaction.scrollState(for: listID).offset.y == 25)
    #expect(harness.context.interaction.selectedLeafID != firstRow)

    for _ in 0..<4 {
      harness.render(content, input: InputState(commands: [.navigation(.up)]))
    }
    #expect(harness.context.interaction.selectedLeafID == firstRow)
    #expect(harness.context.interaction.scrollState(for: listID).offset.y == 0)
  }

  @Test func editingBlocksStructuralNavigation() {
    let harness = Harness()
    let first = FocusTarget()
    let content: LayoutBuilder = { buffer, context in
      let node123 = buffer.focus(
        first, context: context.childScope(0),
        content: { buffer, context in
          return buffer.button(Button("First") {}, context: context)
        })
      let node124 = buffer.button(Button("Second") {}, context: context.childScope(1))
      return buffer.stack([node123, node124], axis: .vertical, context: context)
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
    let content: LayoutBuilder = { buffer, context in
      let node127 = buffer.focus(
        left, context: context.childScope(0).childScope(0),
        content: { buffer, context in
          return buffer.button(Button("Left control") {}, context: context)
        })
      let node128 = buffer.button(
        Button("Left default", role: .defaultAction) { leftCalls += 1 }, context: context.childScope(0).childScope(1))
      let node129 = buffer.stack([node127, node128], axis: .vertical, context: context.childScope(0))
      let node130 = buffer.button(Button("Right control") {}, context: context.childScope(1).childScope(0))
      let node131 = buffer.button(
        Button("Right default", role: .defaultAction) { rightCalls += 1 }, context: context.childScope(1).childScope(1))
      let node132 = buffer.stack([node130, node131], axis: .vertical, context: context.childScope(1))
      return buffer.stack([node129, node132], axis: .horizontal, context: context)
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
    harness.render({ buffer, context in
      let node134 = buffer.textEditor(
        TextEditor(singleLine: true, text: { "text" }, onChange: { _ in }), context: context)
      return node134
    })
    harness.context.interaction.beginEditing(harness.context.interaction.selectedLeafID!, caretOffset: 0)

    harness.render(
      { buffer, context in
        let node135 = buffer.textEditor(
          TextEditor(singleLine: true, text: { "text" }, onChange: { _ in }), context: context)
        return node135
      },
      input: InputState(commands: [.action(.cancel)]))

    #expect(harness.context.interaction.mode == .movement)
  }

  @Test func focusedBindingWinsWithoutRetryingAppBindingsAfterCommandHandling() {
    let harness = Harness()
    let target = FocusTarget()
    var appCalls = 0
    let content: LayoutBuilder = { buffer, context in
      let node137 = buffer.focus(
        target, context: context,
        content: { buffer, context in
          return buffer.button(Button("Control") {}, context: context)
        })
      let node138 = buffer.keyBindings(node137, KeyBindings { bind("x", to: .application("local")) }, context: context)
      let node139 = buffer.onCommand(node138, .application("local"), context: context, action: { .ignored })
      let node140 = buffer.onCommand(
        node139, .application("app"), context: context,
        action: {
          appCalls += 1
          return .handled
        })
      return node140
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
    let content: LayoutBuilder = { buffer, context in
      let node142 = buffer.focus(
        target, context: context,
        content: { buffer, context in
          return buffer.button(Button("Control") {}, context: context)
        })
      let node143 = buffer.keyBindings(node142, KeyBindings { bind("x", to: .application("inner")) }, context: context)
      return buffer.keyBindings(node143, KeyBindings { bind("x", to: .application("outer")) }, context: context)
    }

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
    let control: LayoutBuilder = { buffer, context in
      let node146 = buffer.focus(
        target, context: context,
        content: { buffer, context in
          return buffer.button(Button("Control") {}, context: context)
        })
      return buffer.keyBindings(node146, bindings, context: context)
    }

    target.focus()
    harness.render(control)
    harness.render({ buffer, context in
      let node148 = control(&buffer, context.childScope(0))
      let node149 = buffer.text(Text("Added"), context: context.childScope(1))
      return buffer.stack([node148, node149], axis: .vertical, context: context)
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

    func content() -> LayoutBuilder {
      { buffer, context in
        let scroll = ScrollView(
          data: 0...40, rowHeight: 20, controller: controller,
          build: { buffer, context, index in
            if index < rows.count {
              return buffer.focus(rows[index], context: context) { buffer, context in
                buffer.button(Button("Row \(index)") {}, context: context)
              }
            } else if fieldIsPresent {
              return buffer.focus(field, context: context) { buffer, context in
                buffer.textEditor(
                  TextEditor(singleLine: true, text: { text }, onChange: { text = $0 }), context: context)
              }
            } else {
              return buffer.focus(fallback, context: context) { buffer, context in
                buffer.button(Button("Fallback") {}, context: context)
              }
            }
          })
        var children = [buffer.scrollView(scroll, context: context.childScope(0).keyed(listID))]
        if panelIsOpen {
          children.append(
            buffer.focus(panel, context: context.childScope(1)) { buffer, context in
              buffer.button(Button("Panel") {}, context: context)
            })
        }
        let stack = buffer.stack(children, axis: .vertical, context: context)
        let custom = buffer.onCommand(stack, .application("custom"), context: context) {
          customShortcutCalls += 1
          return .handled
        }
        let open = buffer.onCommand(custom, .application("open-panel"), context: context) {
          panelIsOpen = true
          panel.focus()
          return .handled
        }
        return buffer.onCommand(open, .action(.cancel), context: context) {
          guard panelIsOpen else { return .ignored }
          panelIsOpen = false
          if fieldIsPresent { field.focus() } else { fallback.focus() }
          return .handled
        }
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
    for _ in 0..<15 { press(KeyboardInput(chord: KeyChord("j"))) }
    #expect(rows[15].isFocused)
    #expect(harness.context.interaction.scrollState(for: listID).offset.y > 0)
    for _ in 0..<15 { press(KeyboardInput(chord: KeyChord("f"))) }
    #expect(rows[0].isFocused)
    #expect(harness.context.interaction.scrollState(for: listID).offset.y == 0)

    for _ in 0..<40 { press(KeyboardInput(chord: KeyChord("j"))) }
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
      let field: LayoutBuilder = { buffer, context in
        let node152 = buffer.focus(
          target, context: context,
          content: { buffer, context in
            let node151 = buffer.textEditor(
              TextEditor(singleLine: true, text: { "" }, onChange: { _ in }), context: context)
            return node151
          })
        return buffer.keyBindings(node152, scoped, context: context)
      }
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

@MainActor private struct GridProbe {

  func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let context = context.component(Self.self)
    return buffer.customLeaf(
      context: context, focusRule: focusRule,
      measure: { self.sizeThatFits($0, context: context) },
      register: { self.register(in: $0, context: context) },
      paint: { self.paint(into: &$0, in: $1, context: context) })
  }

  let rows: Int
  let columns: Int
  private let cell: Float = 20

  var focusRule: FocusRule { .container }

  @MainActor func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size {
    Size(width: Float(columns) * cell, height: Float(rows) * cell)
  }

  func register(in rect: Rect, context: LayoutContext) {
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
  func paint(into list: inout DrawList, in rect: Rect, context: LayoutContext) {}
}
