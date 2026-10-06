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
    let list = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(model.actions == 2)
    #expect(model.text == "ac")
    #expect(
      list.paintSnapshot.contains {
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
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
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
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
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
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(runtime.interaction.caretOffset == 1)
  }

  @Test func queuedInputIsFlushedBeforeRendering() {
    let runtime = WindowRuntime()
    let model = InputModel()
    let viewport = Size(width: 100, height: 100)
    runtime.content = DeferredBlock { Text(model.text) }
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.dispatchInput {
      model.text += "a"
      runtime.scheduler.requestContent()
    }
    runtime.dispatchInput { model.text += "b" }
    let list = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(model.text == "ab")
    #expect(
      list.paintSnapshot.contains {
        if case .text(_, "ab", _, _) = $0 { return true }
        return false
      })
    #expect(runtime.scheduler.nextFrame == nil)
    runtime.reset()
  }

  @Test func hoverEventsDoNotPaintUntilPresentation() {
    final class Counter { var draws = 0 }
    struct Probe: PaintableBlock {
      func register(in rect: Rect, context: BlockContext) {}

      let counter: Counter
      var focusRule: FocusRule { .standard }
      @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
      func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
        counter.draws += 1
        list.fillRect(rect, color: .white)
      }
    }
    let counter = Counter()
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let viewport = Size(width: 200, height: 200)
    runtime.content = Probe(counter: counter)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    counter.draws = 0
    for x in 1...100 {
      runtime.handleInput(InputState(pointerPosition: Point(x: Float(x), y: 10)))
    }
    #expect(counter.draws == 0)
    #expect(runtime.interaction.hoveredLeafID != nil)
    #expect(runtime.interaction.input.pointerPosition == Point(x: 100, y: 10))
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(counter.draws == 1)
    #expect(runtime.scheduler.nextFrame == nil)
  }

  @Test func staticIndicatorsDoNotScheduleIdleFrames() throws {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    let target = FocusTarget()
    runtime.content = VStack {
      ProgressIndicator()
      MarqueeText("Overflowing text that stays still")
      TextEditor(text: { "draft" }, onChange: { _ in }).focusTarget(target)
    }
    let viewport = Size(width: 100, height: 100)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    runtime.context.focus(try #require(target.boundID), editing: true)
    let first = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    runtime.scheduler.recordProducedFrame()
    #expect(runtime.scheduler.nextFrame == nil)
    clock.now += 10
    let second = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(first.paintSnapshot == second.paintSnapshot)
    #expect(runtime.scheduler.nextFrame == nil)
    runtime.reset()
  }

  @Test(ControlledObservationDelivery())
  func scrollingAndHoverReturnToIdleAfterObservationDelivery() async {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    let controller = ScrollViewController()
    let viewport = Size(width: 200, height: 200)
    runtime.content = DeferredBlock {
      ScrollView(data: 0..<1_000, rowHeight: 20, controller: controller) { index in
        Text("Row \(index)")
      }
    }
    let onChange: @MainActor @Sendable () -> Void = { runtime.scheduler.requestContent() }
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: onChange)
    await drainObservationChanges()
    #expect(runtime.scheduler.nextFrame == nil)
    for input in [
      InputState(pointerPosition: Point(x: 10, y: 10)),
      InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -20)),
    ] {
      runtime.handleInput(input)
      _ = runtime.renderScheduled(.content, viewport: viewport, onChange: onChange)
      await drainObservationChanges()
      #expect(runtime.scheduler.nextFrame == nil)
    }
    #expect(controller.offset == 20)
  }

  @Test func eventsBeforeInitialFrameAreReplayedInOrder() {
    let runtime = WindowRuntime()
    let model = InputModel()
    runtime.content = Button("Action") { model.actions += 1 }
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    _ = runtime.renderScheduled(.content, viewport: Size(width: 200, height: 100), onChange: {})
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
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: { runtime.scheduler.requestContent() })
    model.text = "one"
    model.text = "two"
    await drainObservationChanges()
    #expect(runtime.scheduler.nextFrame?.deadline == 100 + 1.0 / 60)
    #expect(runtime.scheduler.takeFrame() == nil)
    clock.now = try #require(runtime.scheduler.nextFrame).deadline
    #expect(runtime.scheduler.takeFrame() == .content)
    let list = runtime.renderScheduled(.content, viewport: viewport, onChange: { runtime.scheduler.requestContent() })
    #expect(
      list.paintSnapshot.contains {
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
