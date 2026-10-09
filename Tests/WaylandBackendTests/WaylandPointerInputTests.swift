import Chroma
import Foundation
import Glibc
import Testing

@testable import WaylandBackend

@MainActor
struct WaylandPointerInputTests {
  @MainActor
  final class Harness {
    let input = InputAccumulator()
    var now = 1.0
    var inputs: [InputState] = []
    var onInput: (InputState) -> Void = { _ in }
    lazy var pointer = WaylandPointerInput(
      input: input, clock: { [unowned self] in self.now }, deliver: { [unowned self] in self.deliver() })

    init(version: UInt32 = 5) {
      pointer.configure(version: version)
    }

    func deliver(now: Double? = nil) {
      let state = input.frameInput(now: now ?? pointer.deliveryTime ?? self.now)
      inputs.append(state)
      onInput(state)
    }

    func action(_ action: @escaping (InputAccumulator) -> Void) {
      pointer.dispatchPointer {
        action(self.input)
        self.deliver()
      }
    }

    func fingerSample(x: Float = 0, y: Float = 0, time: UInt32) {
      pointer.scrollSource(isFinger: true)
      if x != 0 { pointer.scrollBy(horizontal: true, delta: x, time: time) }
      if y != 0 { pointer.scrollBy(horizontal: false, delta: y, time: time) }
      pointer.finishFrame()
    }
  }

  final class Capture {
    var registrations = 0
    var paints = 0
    var inputs: [InputState] = []
  }

  struct Probe: PaintableBlock {
    let capture: Capture
    var focusRule: FocusRule { .standard }

    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }

    func register(in rect: Rect, context: BlockContext) {
      capture.registrations += 1
      context.registerInputHandler { capture.inputs.append($0) }
    }

    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      capture.paints += 1
    }
  }

  @Test(arguments: [UInt32(4), UInt32(5)], [false, true])
  func scrollSamplesRefreshOnceWithFrames(version: UInt32, diagonal: Bool) {
    let harness = Harness(version: version)
    let capture = Capture()
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    runtime.content = Probe(capture: capture)
    _ = runtime.renderScheduled(.content, viewport: Size(width: 100, height: 100), onChange: {})
    capture.registrations = 0
    capture.paints = 0
    harness.onInput = { runtime.handleInput($0) }
    if diagonal { harness.pointer.scrollBy(horizontal: true, delta: -5, time: 100) }
    harness.pointer.scrollBy(horizontal: false, delta: -10, time: 100)
    if version == 5 {
      #expect(harness.inputs.isEmpty)
      #expect(capture.registrations == 0)
      #expect(harness.input.frameInput(now: harness.now).scrollDelta == .zero)
    }
    harness.pointer.finishFrame()
    let count = version == 5 || !diagonal ? 1 : 2
    #expect(harness.inputs.count == count)
    #expect(capture.inputs.count == count)
    #expect(capture.registrations == count)
    #expect(capture.paints == 0)
    if version == 5 { #expect(harness.inputs[0].scrollDelta == Point(x: diagonal ? -5 : 0, y: -10)) }
    harness.pointer.finishFrame()
    #expect(harness.inputs.count == count)
    #expect(capture.registrations == count)
    #expect(!harness.pointer.hasPendingFrame)
  }

  @Test(arguments: [false, true])
  func repeatedAxesPreserveSumsAndVelocityWithEarlyOrLateSource(sourceLast: Bool) throws {
    let harness = Harness()
    harness.fingerSample(x: -10, y: -10, time: 100)
    if !sourceLast { harness.pointer.scrollSource(isFinger: true) }
    harness.pointer.scrollBy(horizontal: true, delta: -3, time: 110)
    harness.pointer.scrollBy(horizontal: false, delta: -4, time: 110)
    harness.pointer.scrollBy(horizontal: true, delta: -2, time: 120)
    harness.pointer.scrollBy(horizontal: false, delta: -6, time: 110)
    harness.pointer.scrollBy(horizontal: true, delta: -5, time: 120)
    harness.pointer.stopScroll(horizontal: true, time: 121)
    harness.pointer.stopScroll(horizontal: false, time: 121)
    if sourceLast { harness.pointer.scrollSource(isFinger: true) }
    harness.pointer.finishFrame()
    #expect(harness.inputs.count == 2)
    #expect(try #require(harness.inputs.last).scrollDelta == Point(x: -10, y: -10))
    #expect(harness.input.hasScrollMomentum)
    var horizontal = ScrollMomentum()
    horizontal.record(delta: -10, time: 100)
    horizontal.record(delta: -3, time: 110)
    horizontal.record(delta: -7, time: 120)
    horizontal.stop(time: 121, now: 1)
    var vertical = ScrollMomentum()
    vertical.record(delta: -10, time: 100)
    vertical.record(delta: -10, time: 110)
    vertical.stop(time: 121, now: 1)
    let next = harness.input.frameInput(now: 1.01)
    #expect(abs(next.scrollDelta.x - horizontal.advance(now: 1.01)) < 0.001)
    #expect(abs(next.scrollDelta.y - vertical.advance(now: 1.01)) < 0.001)
  }

  @Test func sameAxisStopThenMovementStartsANewSequence() throws {
    let harness = Harness()
    harness.fingerSample(y: -10, time: 100)
    harness.fingerSample(y: -10, time: 110)
    harness.pointer.stopScroll(horizontal: false, time: 115)
    harness.pointer.scrollBy(horizontal: false, delta: 2, time: 120)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.finishFrame()
    #expect(!harness.input.hasScrollMomentum)
    #expect(try #require(harness.inputs.last).scrollDelta == Point(x: 0, y: 2))
    #expect(harness.input.frameInput(now: 1.01).scrollDelta == .zero)
  }

  @Test func zeroNetSampleDoesNotReusePreviousVelocity() throws {
    let harness = Harness()
    harness.fingerSample(y: -10, time: 100)
    harness.fingerSample(y: -10, time: 110)
    harness.pointer.scrollBy(horizontal: false, delta: -5, time: 120)
    harness.pointer.scrollBy(horizontal: false, delta: 5, time: 120)
    harness.pointer.stopScroll(horizontal: false, time: 125)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.finishFrame()
    #expect(try #require(harness.inputs.last).scrollDelta == .zero)
    #expect(!harness.input.hasScrollMomentum)
  }

  @Test func groupedTimestampsWrapWithoutLosingVelocity() {
    let harness = Harness()
    harness.fingerSample(y: -10, time: UInt32.max - 4)
    harness.pointer.scrollBy(horizontal: false, delta: -3, time: 5)
    harness.pointer.scrollBy(horizontal: false, delta: -7, time: 5)
    harness.pointer.stopScroll(horizontal: false, time: 6)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.finishFrame()
    #expect(harness.input.hasScrollMomentum)
    #expect(harness.input.frameInput(now: 1.01).scrollDelta.y < 0)
  }

  @Test func oneAxisCanStopWhileTheOtherContinues() throws {
    let harness = Harness()
    harness.fingerSample(x: -10, y: -10, time: 100)
    harness.fingerSample(x: -10, y: -10, time: 110)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.stopScroll(horizontal: true, time: 115)
    harness.pointer.scrollBy(horizontal: false, delta: -10, time: 115)
    harness.pointer.finishFrame()
    #expect(harness.input.hasScrollMomentum)
    #expect(try #require(harness.inputs.last).scrollDelta == Point(x: 0, y: -10))
    harness.now = 1.01
    harness.fingerSample(y: -10, time: 120)
    let continued = try #require(harness.inputs.last)
    #expect(continued.scrollDelta.x < 0)
    #expect(continued.scrollDelta.y == -10)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.stopScroll(horizontal: false, time: 125)
    harness.pointer.finishFrame()
    let momentum = harness.input.frameInput(now: 1.02)
    #expect(momentum.scrollDelta.x < 0)
    #expect(momentum.scrollDelta.y < 0)
  }

  @Test(arguments: [false, true])
  func wheelAndUnknownSourcesDoNotInheritFingerMomentum(includeWheelSource: Bool) throws {
    let harness = Harness()
    harness.fingerSample(y: -10, time: 100)
    harness.fingerSample(y: -10, time: 110)
    harness.pointer.scrollBy(horizontal: false, delta: -5, time: 120)
    harness.pointer.stopScroll(horizontal: false, time: 125)
    if includeWheelSource { harness.pointer.scrollSource(isFinger: false) }
    harness.pointer.finishFrame()
    #expect(try #require(harness.inputs.last).scrollDelta == Point(x: 0, y: -5))
    #expect(!harness.input.hasScrollMomentum)
    #expect(harness.input.frameInput(now: 1.01).scrollDelta == .zero)
  }

  @Test func stopWithoutSourceUsesTheActiveAxisSequence() {
    let harness = Harness()
    harness.fingerSample(y: -10, time: 100)
    harness.fingerSample(y: -10, time: 110)
    harness.pointer.stopScroll(horizontal: false, time: 115)
    harness.pointer.finishFrame()
    #expect(harness.input.hasScrollMomentum)
    #expect(harness.input.frameInput(now: 1.01).scrollDelta.y < 0)
  }

  @Test func aNewGestureCancelsMomentumOnBothAxes() throws {
    let harness = Harness()
    harness.fingerSample(x: -10, y: -10, time: 100)
    harness.fingerSample(x: -10, y: -10, time: 110)
    harness.pointer.stopScroll(horizontal: true, time: 115)
    harness.pointer.stopScroll(horizontal: false, time: 115)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.finishFrame()
    #expect(harness.input.hasScrollMomentum)
    harness.now = 1.01
    harness.fingerSample(y: 2, time: 120)
    #expect(!harness.input.hasScrollMomentum)
    #expect(try #require(harness.inputs.last).scrollDelta == Point(x: 0, y: 2))
  }

  @Test func pointerEdgesAndInterleavedActionsStayOrdered() throws {
    let harness = Harness()
    harness.action { $0.pointerEntered(x: 10, y: 20) }
    harness.pointer.scrollBy(horizontal: true, delta: -5, time: 100)
    harness.pointer.scrollBy(horizontal: false, delta: -10, time: 100)
    var keyboardInputs: [InputState] = []
    harness.pointer.dispatchOrdered {
      keyboardInputs.append(harness.input.frameInput(now: harness.now))
    }
    harness.action { $0.pointerPressed() }
    harness.action { $0.pointerMoved(x: 30, y: 40) }
    harness.action { $0.pointerReleased() }
    harness.action { $0.pointerPressed() }
    harness.action { $0.pointerReleased() }
    harness.action { $0.pointerLeft() }
    harness.action { $0.pointerEntered(x: 50, y: 60) }
    #expect(harness.inputs.isEmpty)
    #expect(keyboardInputs.isEmpty)
    harness.pointer.finishFrame()
    #expect(harness.inputs.count == 9)
    #expect(harness.inputs[1].scrollDelta == Point(x: -5, y: -10))
    #expect(try #require(keyboardInputs.first).scrollDelta == .zero)
    #expect(keyboardInputs[0].pointerPosition == Point(x: 10, y: 20))
    #expect(harness.inputs[2].pointerPressed)
    #expect(harness.inputs[2].pointerPressPosition == Point(x: 10, y: 20))
    #expect(harness.inputs[3].pointerDown)
    #expect(harness.inputs[3].pointerPosition == Point(x: 30, y: 40))
    #expect(harness.inputs[4].pointerReleased)
    #expect(harness.inputs[5].pointerPressed)
    #expect(harness.inputs[6].pointerReleased)
    #expect(harness.inputs[7].pointerPosition == Point(x: -1, y: -1))
    #expect(harness.inputs[8].pointerPosition == Point(x: 50, y: 60))
    #expect(harness.inputs.dropFirst(2).allSatisfy { $0.scrollDelta == .zero })
    harness.pointer.finishFrame()
    #expect(harness.inputs.count == 9)
  }

  @Test func interleavingSplitsSamplesWithoutLeakingScrollIntoCommands() {
    let harness = Harness()
    var commands = 0
    harness.pointer.scrollBy(horizontal: true, delta: -5, time: 100)
    harness.pointer.dispatchOrdered {
      #expect(harness.inputs.count == 1)
      #expect(harness.input.frameInput(now: harness.now).scrollDelta == .zero)
      commands += 1
    }
    harness.pointer.scrollBy(horizontal: false, delta: -10, time: 100)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.finishFrame()
    #expect(commands == 1)
    #expect(harness.inputs.map(\.scrollDelta) == [Point(x: -5, y: 0), Point(x: 0, y: -10)])
    harness.pointer.dispatchOrdered { commands += 1 }
    #expect(commands == 2)
  }

  @Test func interleavedRunsPreserveVelocityForTheSameTimestamp() {
    let harness = Harness()
    harness.fingerSample(y: -10, time: 100)
    harness.pointer.scrollBy(horizontal: false, delta: -3, time: 110)
    harness.pointer.dispatchOrdered { #expect(harness.input.frameInput(now: harness.now).scrollDelta == .zero) }
    harness.pointer.scrollBy(horizontal: false, delta: -7, time: 110)
    harness.pointer.stopScroll(horizontal: false, time: 115)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.finishFrame()
    var combined = ScrollMomentum()
    combined.record(delta: -10, time: 100)
    combined.record(delta: -10, time: 110)
    combined.stop(time: 115, now: 1)
    #expect(abs(harness.input.frameInput(now: 1.01).scrollDelta.y - combined.advance(now: 1.01)) < 0.001)
  }

  @Test(arguments: [false, true])
  func groupedClicksAndKeyboardUseFreshCallbacks(beforeInitialFrame: Bool) {
    let harness = Harness()
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    final class Model { var actions = 0 }
    let model = Model()
    runtime.content = DeferredBlock {
      let count = model.actions
      return Button("Increment") { model.actions = count + 1 }
    }
    runtime.keyBindings = KeyBindings { bind("j", to: .action(.activate)) }
    let viewport = Size(width: 200, height: 100)
    if !beforeInitialFrame { _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {}) }
    harness.onInput = { runtime.handleInput($0) }
    harness.action { $0.pointerEntered(x: 5, y: 5) }
    for _ in 0..<2 {
      harness.action { $0.pointerPressed() }
      harness.action { $0.pointerReleased() }
    }
    harness.pointer.scrollBy(horizontal: true, delta: -5, time: 100)
    harness.pointer.scrollBy(horizontal: false, delta: -10, time: 100)
    for _ in 0..<2 {
      harness.pointer.dispatchOrdered {
        runtime.handleKeyboardInput(KeyboardInput(chord: KeyChord("j"))) { resolved in
          if case .command(let command) = resolved { runtime.handleInput(InputState(commands: [command])) }
        }
      }
    }
    harness.pointer.finishFrame()
    if !beforeInitialFrame { #expect(model.actions == 4) }
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(model.actions == 4)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(model.actions == 4)
  }

  @Test(arguments: [false, true])
  func pointerMovementTargetsFreshGeometryBeforePresentation(beforeInitialFrame: Bool) {
    let harness = Harness()
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    final class Model {
      var topHeight: Float = 20
      var actions = 0
    }
    let model = Model()
    runtime.content = DeferredBlock {
      VStack(spacing: 0) {
        Color.white.sizing(x: .fixed(100), y: .fixed(model.topHeight))
        Button("Action") { model.actions += 1 }
      }
    }
    let viewport = Size(width: 200, height: 200)
    if !beforeInitialFrame { _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {}) }
    harness.onInput = { runtime.handleInput($0) }
    harness.action { $0.pointerEntered(x: 5, y: 30) }
    harness.pointer.dispatchOrdered { model.topHeight = 80 }
    harness.action { $0.pointerMoved(x: 5, y: 85) }
    harness.action { $0.pointerPressed() }
    harness.action { $0.pointerReleased() }
    harness.pointer.finishFrame()
    if !beforeInitialFrame { #expect(model.actions == 1) }
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(model.actions == 1)
  }

  @Test(arguments: [false, true])
  func interleavedClipboardCompletionUsesTheCurrentEditingSession(changesEditor: Bool) throws {
    let harness = Harness()
    let runtime = WindowRuntime()
    let keyboard = WaylandKeyboard()
    defer {
      keyboard.cleanup()
      runtime.reset()
    }
    let keymap = """
      xkb_keymap {
        xkb_keycodes { include "evdev+aliases(qwerty)" };
        xkb_types { include "complete" };
        xkb_compatibility { include "complete" };
        xkb_symbols { include "pc+us+inet(evdev)" };
      };
      """ + "\0"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data(keymap.utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let fd = url.path.withCString { unsafe open($0, O_RDONLY) }
    try #require(fd >= 0)
    keyboard.installKeymap(fd: fd, size: UInt32(keymap.utf8.count))
    keyboard.updateModifiers(depressed: 4, latched: 0, locked: 0, group: 0)
    let bindings = KeyBindings { bind("v", modifiers: .control, to: .editing(.paste)) }
    keyboard.resolve = { bindings.resolve($0, isTextEditing: $1) }
    final class Model {
      var first = "a"
      var second = "b"
    }
    let model = Model()
    let first = FocusTarget()
    let second = FocusTarget()
    runtime.content = VStack {
      TextEditor(singleLine: true, text: { model.first }, onChange: { model.first = $0 }).focusTarget(first)
      TextEditor(singleLine: true, text: { model.second }, onChange: { model.second = $0 }).focusTarget(second)
    }
    first.focus(editing: true)
    _ = runtime.renderScheduled(.content, viewport: Size(width: 200, height: 100), onChange: {})
    #expect(first.isEditing)
    let pasteSession = runtime.interaction.editingSessionGeneration
    var pasteID: Int32?
    keyboard.onPaste = { pasteID = $0 }
    harness.onInput = { runtime.handleInput($0) }
    keyboard.onInputAvailable = {
      harness.input.drainKeyboard(keyboard, editingSession: runtime.interaction.editingSessionGeneration)
      harness.deliver()
    }
    keyboard.keyPressed(47, editing: true, editingSession: pasteSession, now: 1)
    let id = try #require(pasteID)
    harness.inputs.removeAll()
    harness.pointer.scrollBy(horizontal: true, delta: -5, time: 100)
    harness.pointer.scrollBy(horizontal: false, delta: -10, time: 100)
    harness.action { _ in
      if changesEditor {
        second.focus(editing: true)
        runtime.handleInput(InputState(textEvents: [.insert("")]))
        #expect(second.isEditing)
      }
    }
    harness.pointer.dispatchOrdered {
      let sessionIsCurrent = runtime.interaction.editingSessionGeneration == pasteSession
      keyboard.completePaste(id: id, text: sessionIsCurrent ? "pasted" : nil)
      harness.input.drainKeyboard(keyboard, editingSession: runtime.interaction.editingSessionGeneration)
      harness.deliver()
    }
    #expect(model.first == "a")
    harness.pointer.finishFrame()
    #expect(model.first == (changesEditor ? "a" : "apasted"))
    #expect(model.second == "b")
    #expect(harness.inputs[0].scrollDelta == Point(x: -5, y: -10))
    #expect(harness.inputs.last?.scrollDelta == .zero)
    #expect(harness.inputs.last?.textEvents == (changesEditor ? [] : [.insert("pasted")]))
    _ = runtime.renderScheduled(.content, viewport: Size(width: 200, height: 100), onChange: {})
    #expect(model.first == (changesEditor ? "a" : "apasted"))
  }

  @Test(arguments: [UInt32(1), UInt32(4)])
  func olderPointersDeliverImmediatelyWithoutReplay(version: UInt32) {
    let harness = Harness(version: version)
    harness.action { $0.pointerEntered(x: 10, y: 20) }
    #expect(harness.inputs.count == 1)
    harness.pointer.scrollBy(horizontal: true, delta: -5, time: 100)
    #expect(harness.inputs.count == 2)
    harness.pointer.scrollBy(horizontal: false, delta: -10, time: 100)
    #expect(harness.inputs.count == 3)
    harness.action { $0.pointerPressed() }
    harness.action { $0.pointerReleased() }
    #expect(harness.inputs.count == 5)
    #expect(harness.inputs[3].pointerPressed)
    #expect(harness.inputs[4].pointerReleased)
    harness.pointer.finishFrame()
    #expect(harness.inputs.count == 5)
    #expect(!harness.pointer.hasPendingFrame)
  }

  @Test(arguments: [false, true])
  func pressAndLeaveCancelMomentum(leaving: Bool) {
    let harness = Harness()
    harness.fingerSample(y: -10, time: 100)
    harness.fingerSample(y: -10, time: 110)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.stopScroll(horizontal: false, time: 115)
    harness.pointer.finishFrame()
    #expect(harness.input.hasScrollMomentum)
    harness.action {
      if leaving { $0.pointerLeft() } else { $0.pointerPressed() }
    }
    harness.pointer.finishFrame()
    #expect(!harness.input.hasScrollMomentum)
    #expect(harness.input.frameInput(now: 1.01).scrollDelta == .zero)
  }

  @Test func resetDropsPendingEventsAndMomentumBeforeReconnect() {
    let harness = Harness()
    harness.fingerSample(y: -10, time: 100)
    harness.fingerSample(y: -10, time: 110)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.stopScroll(horizontal: false, time: 115)
    harness.pointer.finishFrame()
    #expect(harness.input.hasScrollMomentum)
    harness.pointer.scrollBy(horizontal: false, delta: -20, time: 120)
    var actions = 0
    harness.action { _ in actions += 1 }
    harness.pointer.dispatchOrdered { actions += 1 }
    harness.pointer.reset()
    harness.pointer.finishFrame()
    #expect(actions == 0)
    #expect(harness.inputs.count == 3)
    #expect(!harness.pointer.hasPendingFrame)
    #expect(!harness.input.hasScrollMomentum)
    let reset = harness.input.frameInput(now: 1.01)
    #expect(reset.pointerPosition == Point(x: -1, y: -1))
    #expect(!reset.pointerDown && !reset.pointerPressed && !reset.pointerReleased)
    #expect(reset.scrollDelta == .zero)
    harness.pointer.configure(version: 4)
    harness.pointer.scrollBy(horizontal: false, delta: 2, time: 200)
    #expect(harness.inputs.last?.scrollDelta == Point(x: 0, y: 2))
    #expect(!harness.pointer.hasPendingFrame)
  }

  @Test func groupedMomentumReturnsRuntimeToIdle() {
    let harness = Harness()
    let runtime = WindowRuntime(clock: { harness.now })
    defer { runtime.reset() }
    runtime.content = Probe(capture: Capture())
    let viewport = Size(width: 100, height: 100)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    harness.onInput = {
      runtime.handleInput($0)
      runtime.scheduler.scrollMomentumActive = harness.input.hasScrollMomentum
    }
    harness.fingerSample(y: -10, time: 100)
    harness.fingerSample(y: -10, time: 110)
    harness.pointer.scrollSource(isFinger: true)
    harness.pointer.stopScroll(horizontal: false, time: 115)
    harness.pointer.finishFrame()
    #expect(runtime.scheduler.scrollMomentumActive)
    for frame in 1...150 {
      harness.now = 1 + Double(frame) / 100
      harness.deliver()
      _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    }
    #expect(!runtime.scheduler.scrollMomentumActive)
    #expect(runtime.scheduler.nextFrame == nil)
    #expect(!harness.pointer.hasPendingFrame)
    #expect(harness.input.frameInput(now: harness.now).scrollDelta == .zero)
  }
}
