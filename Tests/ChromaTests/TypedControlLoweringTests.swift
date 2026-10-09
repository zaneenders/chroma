import Testing

@testable import Chroma

@MainActor
struct TypedControlLoweringTests {
  private let rect = Rect(x: 0, y: 0, width: 200, height: 80)

  @Test func idleMeasurementAndRegistrationShareOneChild() {
    let context = LayoutContext()
    var phases: [InteractionPhase] = []
    var buffer = LayoutBuffer()
    let node = buffer.interactive(
      action: {},
      content: { buffer, context, phase in
        phases.append(phase)
        return buffer.text(Text("same child"), context: context)
      }, context: context)
    _ = buffer.expandsHorizontally(node)
    _ = buffer.expandsVertically(node)
    _ = buffer.sizeThatFits(node, rect.size)
    context.interaction.beginFrame(input: InputState())
    buffer.register(node, in: rect)
    var list = DrawList()
    buffer.paint(node, into: &list, in: rect)
    buffer.paint(node, into: &list, in: rect)
    #expect(phases == [.idle])
    #expect(buffer.count == 2)
    #expect(context.interaction.builderRoot?.children.count == 1)
    context.interaction.endFrame()
  }

  @Test func eachPhaseIsLoweredOnceWithinTheOperation() {
    let context = LayoutContext()
    var phases: [InteractionPhase] = []
    var buffer = LayoutBuffer()
    var node = InteractiveNode(
      id: nil, action: {},
      content: { buffer, context, phase in
        phases.append(phase)
        return buffer.text(Text("\(phase)"), context: context)
      }, context: context)
    let idle = node.child(for: .idle, in: &buffer)
    let hovered = node.child(for: .hovered, in: &buffer)
    let pressed = node.child(for: .pressed, in: &buffer)
    let idleAgain = node.child(for: .idle, in: &buffer)
    let pressedAgain = node.child(for: .pressed, in: &buffer)
    let hoveredAgain = node.child(for: .hovered, in: &buffer)
    #expect(idleAgain == idle)
    #expect(pressedAgain == pressed)
    #expect(hoveredAgain == hovered)
    #expect(phases == [.idle, .hovered, .pressed])
    #expect(buffer.count == 3)
  }

  @Test func paintKeepsRegisteredPhaseAndDoesNotResolveOrRegisterAgain() {
    let context = LayoutContext()
    let id = WidgetID("phase")
    var phases: [InteractionPhase] = []
    var buffer = LayoutBuffer()
    let node = buffer.interactive(
      id: id, action: {},
      content: { buffer, context, phase in
        phases.append(phase)
        return buffer.text(Text("\(phase)"), context: context)
      }, context: context)
    _ = buffer.sizeThatFits(node, rect.size)
    context.interaction.hoveredLeafID = id
    context.interaction.beginFrame(input: InputState())
    buffer.register(node, in: rect)
    let registeredCount = context.interaction.builderRoot?.children.count
    let nodeCount = buffer.count
    context.interaction.hoveredLeafID = nil
    var list = DrawList()
    buffer.paint(node, into: &list, in: rect)
    buffer.paint(node, into: &list, in: rect)
    #expect(phases == [.idle, .hovered])
    #expect(buffer.count == nodeCount)
    #expect(context.interaction.builderRoot?.children.count == registeredCount)
    #expect(
      list.paintSnapshot.allSatisfy {
        if case .text(_, "hovered", _, _) = $0 { return true }
        return false
      })
    context.interaction.endFrame()
  }

  @Test func editorReadsBindingOnceAcrossLayoutRegistrationAndDrawing() throws {
    let context = LayoutContext()
    var reads = 0
    var text = "a👨‍👩‍👧‍👦e\u{301}"
    let snapshot = text
    let editor = TextEditor(
      text: {
        reads += 1
        return text
      }, onChange: { text = $0 })
    var buffer = LayoutBuffer()
    let node = buffer.textEditor(editor, context: context)
    #expect(reads == 1)
    text = "later binding value"
    _ = buffer.sizeThatFits(node, rect.size)
    _ = buffer.sizeThatFits(node, Size(width: 100, height: 80))
    context.interaction.beginFrame(input: InputState())
    buffer.register(node, in: rect)
    context.interaction.endFrame()
    let id = try #require(context.interaction.tree?.children.first?.leafID)
    context.focus(id, editing: true)
    context.interaction.caretOffset = 99
    context.interaction.textSelectionRange = 1..<99
    context.interaction.beginFrame(input: InputState())
    buffer.register(node, in: rect)
    var list = DrawList()
    buffer.paint(node, into: &list, in: rect)
    buffer.paint(node, into: &list, in: rect)
    #expect(reads == 1)
    #expect(context.interaction.editingText == snapshot)
    #expect(context.interaction.caretOffset == 3)
    #expect(context.interaction.textSelectionRange == 1..<3)
    #expect(
      list.paintSnapshot.contains {
        if case .text(_, let value, _, _) = $0 { return value == snapshot }
        return false
      })
    context.interaction.endFrame()
    buffer.reset()
    let fresh = buffer.textEditor(editor, context: context)
    #expect(reads == 2)
    context.interaction.beginFrame(input: InputState())
    buffer.register(fresh, in: rect)
    #expect(context.interaction.editingText == text)
    context.interaction.endFrame()
  }

  @Test func resetReplacesControlCallbacksBeforeAnotherInputEvent() {
    let context = LayoutContext()
    var actions: [String] = []
    var buffer = LayoutBuffer()
    func action(_ value: String) -> Button {
      Button(value, id: WidgetID("action"), action: { actions.append(value) })
    }
    let first = buffer.button(action("first"), context: context)
    context.interaction.beginFrame(input: InputState())
    buffer.register(first, in: rect)
    context.interaction.endFrame()
    let point = Point(x: 10, y: 10)
    context.interaction.processInput(
      InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    buffer.reset()
    let second = buffer.button(action("second"), context: context)
    context.interaction.beginFrame(input: InputState())
    buffer.register(second, in: rect)
    context.interaction.endFrame()
    context.interaction.processInput(InputState(pointerPosition: point, pointerReleased: true))
    context.interaction.finishInput()
    #expect(actions == ["second"])
  }

  @Test func directModifiersPreserveDrawingOrderAndClippedActions() {
    var activations = 0
    let insets = EdgeInsets(leading: -20, trailing: -20)
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    let background = buffer.background(
      context: context,
      content: { buffer, context in
        let control = buffer.interactive(
          action: { activations += 1 },
          content: { buffer, context, phase in buffer.text(Text("\(phase)"), context: context) },
          context: context)
        return buffer.padding(control, insets, context: context)
      }, background: { buffer, context in buffer.color(.black, context: context) })
    let rounded = buffer.roundedBackground(background, color: .black, radii: CornerRadii(3), context: context)
    let bordered = buffer.border(rounded, color: .white, radii: CornerRadii(4), width: 2, context: context)
    let root = buffer.clip(bordered, context: context)
    context.interaction.beginFrame(input: InputState(pointerPosition: Point(x: -100, y: -100)))
    buffer.register(root, in: rect)
    var list = DrawList()
    buffer.paint(root, into: &list, in: rect)
    context.interaction.endFrame()
    #expect(
      list.paintSnapshot == [
        .pushClip(rect),
        .fillRoundedRect(rect: rect, radii: CornerRadii(3), color: .black),
        .fillRect(rect: rect, color: .black),
        .text(position: Point(x: -20, y: 0), text: "idle", color: .white, scale: 1),
        .strokeRoundedRect(rect: rect, radii: CornerRadii(4), width: 2, color: .white),
        .popClip,
      ])
    #expect(activations == 0)
    #expect(context.interaction.tree?.children.count == 1)
    for point in [Point(x: -5, y: 5), Point(x: 5, y: 5)] {
      context.interaction.processInput(
        InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
      context.interaction.processInput(InputState(pointerPosition: point, pointerReleased: true))
      context.interaction.finishInput()
      #expect(activations == (point.x < 0 ? 0 : 1))
    }
  }

  @Test func directGroupFocusAndCommandScopesPreserveBehavior() {
    var activations = 0
    var commands = 0
    let target = FocusTarget()
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    let root = buffer.group("Actions", context: context) { buffer, context in
      let child = buffer.focus(target, context: context) { buffer, context in
        buffer.button(Button("Run", action: { activations += 1 }), context: context)
      }
      let bound = buffer.keyBindings(child, .modalNavigation, context: context)
      return buffer.onCommand(bound, .action(.submit), context: context) {
        commands += 1
        return .handled
      }
    }
    target.focus()
    context.interaction.beginFrame(input: InputState())
    buffer.register(root, in: rect)
    context.interaction.endFrame()
    #expect(target.isFocused)
    context.interaction.processInput(InputState(commands: [.action(.submit)]))
    #expect(commands == 1)
    #expect(activations == 0)
    context.interaction.processInput(InputState(commands: [.action(.activate)]))
    #expect(activations == 1)
  }

  @Test func directTrailingControlsAndSizingPlaceExactGeometry() {
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    let root = buffer.trailingControls(
      spacing: 6, context: context,
      input: { buffer, context in
        let text = buffer.text(Text("input"), context: context)
        return buffer.sizing(text, x: .grow, y: .fixed(40), context: context)
      },
      controls: { buffer, context in
        let text = buffer.text(Text("send"), context: context)
        return buffer.padding(text, 3, context: context)
      })
    let measured = buffer.sizeThatFits(root, rect.size)
    #expect(measured == Size(width: 200, height: 40))
    context.interaction.beginFrame(input: InputState())
    buffer.register(root, in: rect)
    var list = DrawList()
    buffer.paint(root, into: &list, in: rect)
    context.interaction.endFrame()
    #expect(
      list.paintSnapshot == [
        .text(position: Point(x: 0, y: 40), text: "input", color: .white, scale: 1),
        .text(position: Point(x: 149, y: 49), text: "send", color: .white, scale: 1),
      ])
  }

  @Test func directAnimationSamplesOnceAndRetargetsContinuously() {
    let context = LayoutContext()
    var buffer = LayoutBuffer()
    var samples: [Float] = []
    for (time, target): (Double, Float) in [(0, 10), (0, 110), (0.5, 110), (0.5, 10), (1, 10), (1.5, 10)] {
      buffer.reset()
      context.interaction.animationTime = time
      let animated = buffer.animatedValue(target, duration: 1, context: context.keyed("animation")) {
        buffer, context, value in
        samples.append(value)
        let color = buffer.color(.white, context: context)
        return buffer.sizing(color, x: .fixed(value), y: .fixed(10), context: context)
      }
      let root = buffer.stack([animated], axis: .vertical, context: context)
      _ = buffer.sizeThatFits(root, rect.size)
      context.interaction.beginFrame(input: InputState())
      buffer.register(root, in: rect)
      context.interaction.endFrame()
      let count = samples.count
      var list = DrawList()
      buffer.paint(root, into: &list, in: rect)
      buffer.paint(root, into: &list, in: rect)
      #expect(samples.count == count)
    }
    #expect(samples == [10, 10, 60, 60, 35, 10])
    #expect(!context.interaction.animationsActive)
  }

  @Test func firstInputRootReplacementClearsBootstrapRegistrations() {
    let runtime = WindowRuntime()
    var actions = 0
    runtime.build = { buffer, context in
      let child = buffer.text(Text("before"), context: context)
      return buffer.onCommand(child, .action(.submit), context: context) {
        actions += 1
        runtime.build = nil
        #expect(runtime.interaction.tree == nil)
        return .handled
      }
    }
    let list = runtime.render(
      viewport: rect.size, input: InputState(commands: [.action(.submit)]), onChange: {})
    #expect(actions == 1)
    #expect(list.commands.isEmpty)
    runtime.reset()
  }

  @Test func directActionRootReplacementDrawsNewRootWithoutReplayingInput() {
    let runtime = WindowRuntime()
    var actions = 0
    runtime.build = { buffer, context in
      buffer.interactive(
        action: {
          actions += 1
          runtime.build = { buffer, context in
            buffer.interactive(
              action: { actions += 100 },
              content: { buffer, context, _ in buffer.text(Text("after"), context: context) },
              context: context)
          }
        },
        content: { buffer, context, _ in buffer.text(Text("before"), context: context) },
        context: context)
    }
    _ = runtime.render(viewport: rect.size, input: InputState(), onChange: {})
    let point = Point(x: 5, y: 5)
    _ = runtime.render(
      viewport: rect.size,
      input: InputState(pointerPosition: point, pointerDown: true, pointerPressed: true), onChange: {})
    let list = runtime.render(
      viewport: rect.size, input: InputState(pointerPosition: point, pointerReleased: true), onChange: {})
    let labels = list.paintSnapshot.compactMap { entry -> String? in
      if case .text(_, let value, _, _) = entry { return value }
      return nil
    }
    #expect(labels == ["after"])
    #expect(actions == 1)
    runtime.reset()
  }

}
