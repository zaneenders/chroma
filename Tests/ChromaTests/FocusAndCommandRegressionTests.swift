import Testing

@testable import Chroma

@MainActor
struct FocusAndCommandRegressionTests {
  @MainActor private final class Harness {
    let context = RenderContext()
    let producer = FrameProducer()

    func render(_ content: any Block, input: InputState = InputState()) {
      _ = producer.render(
        content: content, viewport: Size(width: 200, height: 100),
        input: input, context: context, onChange: {})
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
    let content = BlockBuilder.buildBlock(
      Text("No controls")
        .onCommand(.application("test")) {
          calls += 1
          return .handled
        }
        .id("document"),
      Button("Sibling") {})
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
    harness.render(replacement, input: InputState(commands: [.action(.activate)]))
    #expect(calls == 1)
  }

  @Test func focusRecoversWhenReplacementPathEndsAtGroup() {
    let harness = Harness()
    var calls = 0
    harness.render(Button("Before") {})
    let replacement = VStack { Button("After") { calls += 1 } }
    harness.render(replacement)
    harness.render(replacement, input: InputState(commands: [.action(.activate)]))
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
        Text("Added")
        control
      })

    #expect(harness.context.interaction.selectedLeafID == target.boundID)
    #expect(
      harness.context.interaction.resolve(
        KeyboardInput(chord: KeyChord("x")), appBindings: KeyBindings())
        == .command(.application("local")))
  }
}
