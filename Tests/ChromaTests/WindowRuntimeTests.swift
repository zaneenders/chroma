import ChromaTesting
import Observation
import Testing

@testable import Chroma

@MainActor
struct WindowRuntimeTests {
  @Test func appBindingsReachTheHeadlessRuntime() throws {
    let host = HeadlessHost()
    try BoundApp().run(on: host)
    #expect(host.runtime.resolve(KeyboardInput(chord: KeyChord("j"), text: "j")) == .command(.navigation(.down)))
  }

  @Test func replacingBindingsChangesResolution() {
    let runtime = WindowRuntime()
    runtime.keyBindings = KeyBindings { bind("j", to: .navigation(.down)) }
    let input = KeyboardInput(chord: KeyChord("j"), text: "j")
    #expect(runtime.resolve(input) == .command(.navigation(.down)))
    runtime.keyBindings = KeyBindings { disable("j") }
    #expect(runtime.resolve(input) == nil)
  }

  @Test func observationPreservesHostRasterScale() {
    let runtime = WindowRuntime()
    let viewport = Size(width: 40, height: 30)
    var observations: [FrameObservation] = []
    runtime.frameObserver = { observations.append($0) }
    let list = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.observe(list, viewport: viewport)
    runtime.observe(list, viewport: viewport, rasterScale: Point(x: 2, y: 2))
    #expect(observations.count == 2)
    #expect(observations[0].rasterScale == nil)
    #expect(observations[1].rasterScale == Point(x: 2, y: 2))
    #expect(observations[1].viewport == viewport)
  }
  @Observable final class InputModel {
    var text = ""
    var actions = 0
  }

  @Test func inputIsAppliedImmediatelyAndEveryEventSurvivesCoalescing() throws {
    let runtime = WindowRuntime()
    let model = InputModel()
    let editor = FocusTarget()
    let button = FocusTarget()
    let viewport = Size(width: 300, height: 200)
    runtime.content = VStack {
      TextEditor(singleLine: true, text: { model.text }, onChange: { model.text = $0 }).focusTarget(editor)
      Button("Action") { model.actions += 1 }.focusTarget(button)
    }
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.context.focus(try #require(editor.boundID), editing: true)
    for event: TextEditEvent in [.insert("a"), .insert("b"), .backspace, .insert("c")] {
      runtime.handleInput(InputState(textEvents: [event]))
    }
    #expect(model.text == "ac")
    #expect(runtime.scheduler.nextFrame?.kind == .content)
    runtime.context.focus(try #require(button.boundID))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    #expect(model.actions == 2)
    let list = runtime.renderContent(viewport: viewport, onChange: {})
    #expect(model.actions == 2)
    #expect(model.text == "ac")
    #expect(
      list.commands.contains {
        if case .text(_, "ac", _, _) = $0 { return true }
        return false
      })
    let buttonID = try #require(button.boundID)
    let path = try #require(runtime.interaction.tree?.findLeaf(buttonID))
    let origin = try #require(runtime.interaction.tree?.node(at: path)?.rect.origin)
    let point = Point(x: origin.x + 2, y: origin.y + 2)
    for _ in 0..<2 {
      runtime.handleInput(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
      runtime.handleInput(InputState(pointerPosition: point, pointerReleased: true))
    }
    #expect(model.actions == 4)
    _ = runtime.renderContent(viewport: viewport, onChange: {})
    #expect(model.actions == 4)
    runtime.reset()
  }

  @Test(arguments: [false, true])
  func coalescedActivationsUseCurrentCallbacks(beforeInitialFrame: Bool) {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let model = InputModel()
    let viewport = Size(width: 200, height: 200)
    runtime.content = DeferredBlock {
      let count = model.actions
      return Button("Increment") { model.actions = count + 1 }
    }
    if !beforeInitialFrame {
      _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    }
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    if !beforeInitialFrame { #expect(model.actions == 2) }
    _ = runtime.renderContent(viewport: viewport, onChange: {})
    #expect(model.actions == 2)
  }

  @Test func coalescedVerticalMovementUsesUpdatedTextLayout() throws {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let model = InputModel()
    model.text = "a"
    let editor = FocusTarget()
    let viewport = Size(width: 200, height: 200)
    runtime.content = TextEditor(text: { model.text }, onChange: { model.text = $0 }).focusTarget(editor)
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.context.focus(try #require(editor.boundID), editing: true)
    runtime.handleInput(InputState(textEvents: [.insert("\nb")]))
    runtime.handleInput(InputState(textEvents: [.moveCaretUp]))
    #expect(model.text == "a\nb")
    #expect(runtime.interaction.caretOffset == 1)
    _ = runtime.renderContent(viewport: viewport, onChange: {})
    #expect(runtime.interaction.caretOffset == 1)
  }

  @Test func queuedInputSupersedesAnAlreadyRunnableAnimation() throws {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    let model = InputModel()
    let viewport = Size(width: 100, height: 100)
    runtime.content = DeferredBlock { ProgressIndicator(); Text(model.text) }
    _ = runtime.renderScheduled(viewport: viewport, onChange: {})
    clock.now = try #require(runtime.scheduler.nextFrame).deadline
    #expect(runtime.scheduler.nextFrame?.kind == .animation)
    runtime.dispatchInput { model.text += "a" }
    runtime.dispatchInput { model.text += "b" }
    let list = runtime.renderScheduled(viewport: viewport, onChange: {})
    #expect(model.text == "ab")
    #expect(list?.commands.contains {
      if case .text(_, "ab", _, _) = $0 { return true }
      return false
    } == true)
    #expect(runtime.scheduler.nextFrame?.kind == .animation)
    #expect(runtime.scheduler.nextFrame?.deadline == clock.now + 1.0 / 30)
    #expect(runtime.scheduler.takeFrame() == nil)
    runtime.reset()
  }

  @Test func queuedInputCanRequestContentOnlyWhenFlushed() throws {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    let viewport = Size(width: 100, height: 100)
    runtime.content = ProgressIndicator()
    #expect(runtime.scheduler.takeFrame() == .content)
    _ = runtime.renderContent(viewport: viewport, onChange: {})
    clock.now = try #require(runtime.scheduler.nextFrame).deadline
    #expect(runtime.scheduler.nextFrame?.kind == .animation)
    runtime.dispatchInput(requestsFrame: false) {
      runtime.content = Text("Updated by input")
    }
    #expect(!runtime.scheduler.hasContentRequest)
    let produced = runtime.renderScheduled(viewport: viewport, onChange: {})
    let list = try #require(produced)
    #expect(list.commands.contains {
      if case .text(_, "Updated by input", _, _) = $0 { return true }
      return false
    })
    #expect(!runtime.needsAnimationFrame)
    #expect(!runtime.scheduler.animationsActive)
    #expect(!runtime.scheduler.inputPending)
    #expect(runtime.scheduler.nextFrame == nil)
    runtime.reset()
  }

  @Test func hostInputPreparationRunsBeforeSelectionAndFlushesItsQueuedActions() throws {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    let viewport = Size(width: 100, height: 100)
    runtime.content = ProgressIndicator()
    _ = runtime.renderScheduled(viewport: viewport, onChange: {})
    clock.now = try #require(runtime.scheduler.nextFrame).deadline
    var order: [Int] = []
    runtime.dispatchInput(requestsFrame: false) { order.append(1) }
    let list = runtime.renderScheduled(
      viewport: viewport,
      prepareInput: {
        order.append(2)
        runtime.dispatchInput(requestsFrame: false) {
          order.append(3)
          runtime.content = Text("Prepared input")
        }
      }, onChange: {})
    #expect(order == [1, 2, 3])
    #expect(list?.commands.contains {
      if case .text(_, "Prepared input", _, _) = $0 { return true }
      return false
    } == true)
    #expect(!runtime.scheduler.inputPending)
    runtime.reset()
  }

  @Test func inputPreparationCannotBypassTheGlobalCap() {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    let viewport = Size(width: 100, height: 100)
    runtime.content = ProgressIndicator()
    _ = runtime.renderScheduled(viewport: viewport, onChange: {})
    clock.now += 0.001
    let list = runtime.renderScheduled(
      viewport: viewport,
      prepareInput: { runtime.scheduler.requestContent() }, onChange: {})
    #expect(list == nil)
    #expect(runtime.scheduler.lastFrameTime == 100)
    #expect(runtime.scheduler.nextFrame?.kind == .content)
    #expect(runtime.scheduler.nextFrame?.deadline == 100 + 1.0 / 60)
    clock.now = 100 + 1.0 / 60
    let produced = runtime.renderScheduled(viewport: viewport, onChange: {})
    #expect(produced != nil)
    runtime.reset()
  }

  @Test func inputCanCancelAnimationDemandBeforeSelection() throws {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    let viewport = Size(width: 100, height: 100)
    runtime.content = ProgressIndicator()
    _ = runtime.renderScheduled(viewport: viewport, onChange: {})
    clock.now = try #require(runtime.scheduler.nextFrame).deadline
    runtime.dispatchInput(requestsFrame: false) { runtime.reset() }
    let produced = runtime.renderScheduled(viewport: viewport, onChange: {})
    #expect(produced == nil)
    #expect(runtime.scheduler.lastFrameTime == nil)
    #expect(runtime.scheduler.nextFrame == nil)
  }

  @Test func animationDemandAndDeadlinesFollowRenderingReplacementAndReset() {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    let viewport = Size(width: 100, height: 100)
    runtime.content = ProgressIndicator()
    #expect(runtime.nextAnimationDeadline == nil)
    #expect(runtime.scheduler.takeFrame() == .content)
    _ = runtime.renderContent(viewport: viewport, onChange: {})
    #expect(runtime.scheduler.animationsActive)
    #expect(runtime.nextAnimationDeadline == 100 + 1.0 / 30)
    runtime.scheduler.setRefreshRates(minimum: 20, maximum: 60)
    runtime.scheduler.requestContent()
    #expect(runtime.nextAnimationDeadline == 100 + 1.0 / 20)
    #expect(runtime.nextAnimationDeadline == runtime.scheduler.animationDeadline)
    runtime.scheduler.contentAnimationActive = true
    _ = runtime.renderAnimations()
    #expect(runtime.scheduler.contentAnimationActive)
    runtime.content = Text("Static")
    #expect(!runtime.scheduler.animationsActive)
    #expect(!runtime.scheduler.contentAnimationActive)
    #expect(runtime.nextAnimationDeadline == nil)
    runtime.scheduler.contentAnimationActive = true
    #expect(runtime.nextAnimationDeadline == 100 + 1.0 / 20)
    runtime.reset()
    #expect(runtime.nextAnimationDeadline == nil)
    #expect(!runtime.scheduler.animationsActive)
    #expect(!runtime.scheduler.contentAnimationActive)
  }

  @Test func registrationPassRestoresThePreviousModeAndDoesNotCollectAnimations() {
    let producer = FrameProducer()
    let interaction = Interaction()
    let context = BlockContext(interaction: interaction)
    let viewport = Size(width: 100, height: 100)
    producer.refreshRegistrations(ProgressIndicator(), viewport: viewport, context: context)
    #expect(interaction.framePass == .painting)
    #expect(interaction.tree != nil)
    #expect(interaction.animationPaints.isEmpty)
    interaction.framePass = .registrations
    producer.refreshRegistrations(ProgressIndicator(), viewport: viewport, context: context)
    #expect(interaction.framePass == .registrations)
    #expect(interaction.animationPaints.isEmpty)
  }

  @Test func backendReadinessNotificationsDoNotTurnAnimationIntoContent() throws {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    let viewport = Size(width: 100, height: 100)
    var builds = 0
    var notifications = 0
    runtime.content = DeferredBlock {
      builds += 1
      return ProgressIndicator()
    }
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.scheduler.consumeContentRequest()
    runtime.scheduler.recordProducedFrame()
    clock.now = try #require(runtime.scheduler.nextFrame).deadline
    let initialBuilds = builds
    runtime.dispatchInput(requestsFrame: false) { notifications += 1 }
    _ = runtime.renderScheduled(viewport: viewport, onChange: {})
    #expect(notifications == 1)
    #expect(builds == initialBuilds)
    runtime.reset()
  }

  @Test func eventsBeforeInitialFrameAreReplayedInOrder() {
    let runtime = WindowRuntime()
    let model = InputModel()
    runtime.content = Button("Action") { model.actions += 1 }
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    _ = runtime.renderContent(viewport: Size(width: 200, height: 100), onChange: {})
    #expect(model.actions == 2)
    runtime.reset()
  }

  @Test(ControlledObservationDelivery())
  func observedChangesCoalesceWithinTheCapAndContentReplacementKeepsFrameHistory() async throws {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    let model = InputModel()
    let viewport = Size(width: 100, height: 100)
    runtime.content = DeferredBlock { Text(model.text) }
    #expect(runtime.scheduler.takeFrame() == .content)
    _ = runtime.renderContent(viewport: viewport, onChange: { runtime.scheduler.requestContent() })
    model.text = "one"
    model.text = "two"
    await drainObservationChanges()
    #expect(runtime.scheduler.nextFrame?.deadline == 100 + 1.0 / 60)
    #expect(runtime.scheduler.takeFrame() == nil)
    clock.now = try #require(runtime.scheduler.nextFrame).deadline
    #expect(runtime.scheduler.takeFrame() == .content)
    let list = runtime.renderContent(viewport: viewport, onChange: { runtime.scheduler.requestContent() })
    #expect(
      list.commands.contains {
        if case .text(_, "two", _, _) = $0 { return true }
        return false
      })
    #expect(runtime.scheduler.nextFrame == nil)
    runtime.content = ProgressIndicator()
    #expect(runtime.scheduler.nextFrame?.deadline == clock.now + 1.0 / 60)
    #expect(runtime.scheduler.takeFrame() == nil)
    runtime.reset()
  }

  @Test func inputDispatchRunsAtUserInitiatedPriority() async {
    let runtime = WindowRuntime()
    let priority = await withCheckedContinuation { continuation in
      runtime.dispatchInput { continuation.resume(returning: Task.currentPriority) }
    }
    #expect(priority >= .userInitiated)
    runtime.reset()
  }

}

private struct BoundApp: App {
  var keyBindings: KeyBindings { KeyBindings { bind("j", to: .navigation(.down)) } }
  var body: some Block { Text("Runtime") }
}
