import Testing

@testable import Chroma

/// Exercises the real runtime with virtual input cost. No native event loop,
/// compositor, physical display, or wall-clock performance claim is involved.
@MainActor
struct InputBacklogTests {
  final class State {
    var applied: [InputState] = []
    var callbackRevisions: [Int] = []
    var paints = 0
    var frames = 0
  }

  @MainActor struct Probe: Block {

    func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        measure: { self.sizeThatFits($0, context: context) },
        register: { self.register(in: $0, context: context) },
        paint: { self.paint(into: &$0, in: $1, context: context) })
    }

    let state: State
    var focusRule: FocusRule { .decorative }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func register(in rect: Rect, context: BlockContext) {
      let revision = state.applied.count
      context.registerInputHandler { input in
        // Ignore registration-only synthetic input and initial/idle input.
        guard
          input.scrollDelta != .zero || !input.textEvents.isEmpty
            || input.pointerPressed || input.pointerReleased
        else { return }
        state.callbackRevisions.append(revision)
        state.applied.append(input)
      }
    }
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      state.paints += 1
    }
  }

  @Test(arguments: [false, true])
  func finiteSynchronousAxisBacklogRecoversWithoutReplayingInput(diagonal: Bool) async {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    defer {
      runtime.scheduler.onFrame = nil
      runtime.reset()
    }
    let state = State()
    runtime.setContent(Probe(state: state))
    let viewport = Size(width: 100, height: 100)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    runtime.scheduler.recordProducedFrame()
    var inputs: [InputState] = []
    for sample in 1...180 {
      // Distinct values expose a dropped input replaced by a duplicate, too.
      let delta = -Float(sample)
      inputs.append(InputState(scrollDelta: Point(x: 0, y: delta)))
      if diagonal { inputs.append(InputState(scrollDelta: Point(x: delta, y: 0))) }
    }
    let samples = inputs
    await withCheckedContinuation { continuation in
      runtime.scheduler.onFrame = { kind in
        state.frames += 1
        #expect(!runtime.scheduler.inputPending)
        #expect(state.applied == samples)
        _ = runtime.renderScheduled(kind, viewport: viewport, onChange: {})
        runtime.scheduler.isReady = false
        continuation.resume()
      }
      runtime.scheduler.isReady = true
      // Models listeners called synchronously inside one non-suspending native
      // dispatch action, not the packet/read batch sizes of libwayland itself.
      runtime.dispatchInput(requestsFrame: false) {
        for input in samples {
          runtime.handleInput(input)
          clock.now += 0.023
          #expect(runtime.scheduler.inputPending)
          #expect(state.frames == 0)
          #expect(runtime.scheduler.hasContentRequest)
        }
      }
    }
    #expect(state.frames == 1)
    #expect(state.paints == 2)
    #expect(state.applied == samples)
    #expect(state.callbackRevisions == Array(samples.indices))
    #expect(runtime.scheduler.nextFrame == nil)
    #expect(abs(clock.now - (100 + Double(samples.count) * 0.023)) < 0.000_001)
    // Advancing the clock alone must not create idle work or a catch-up frame.
    clock.now += 10
    #expect(runtime.scheduler.takeFrame() == nil)
  }

  @Test func reentrantDispatchStaysOrderedAndDrainsBeforeTheRecoveryFrame() async {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    defer {
      runtime.scheduler.onFrame = nil
      runtime.reset()
    }
    var order: [Int] = []
    var frames = 0
    await withCheckedContinuation { continuation in
      runtime.scheduler.onFrame = { kind in
        frames += 1
        #expect(order == [0, 1, 2, 3])
        #expect(!runtime.scheduler.inputPending)
        _ = runtime.renderScheduled(kind, viewport: Size(width: 1, height: 1), onChange: {})
        runtime.scheduler.isReady = false
        continuation.resume()
      }
      runtime.scheduler.isReady = true
      runtime.dispatchInput {
        order.append(0)
        clock.now += 0.023
        runtime.dispatchInput {
          order.append(2)
          clock.now += 0.023
          runtime.dispatchInput { order.append(3) }
        }
        #expect(frames == 0)
      }
      runtime.dispatchInput { order.append(1) }
    }
    #expect(frames == 1)
    #expect(runtime.scheduler.nextFrame == nil)
  }

  @Test(arguments: [false, true])
  func orderedEdgesAndTextSurviveBacklogBeforeAndAfterInitialFrame(beforeInitialFrame: Bool) {
    let runtime = WindowRuntime()
    defer {
      runtime.scheduler.onFrame = nil
      runtime.reset()
    }
    let state = State()
    runtime.setContent(Probe(state: state))
    let viewport = Size(width: 100, height: 100)
    if !beforeInitialFrame {
      _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    }
    let inputs = [
      InputState(pointerPosition: Point(x: 10, y: 10), pointerDown: true, pointerPressed: true),
      InputState(pointerPosition: Point(x: 20, y: 20), pointerReleased: true),
      InputState(textEvents: [.insert("a")]),
      InputState(textEvents: [.insert("b")]),
      InputState(textEvents: [.backspace]),
      InputState(textEvents: [.insert("c")]),
    ]
    for input in inputs { runtime.dispatchInput { runtime.handleInput(input) } }
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(state.applied == inputs)
    #expect(state.callbackRevisions == Array(inputs.indices))
    #expect(!runtime.scheduler.inputPending)
    #expect(runtime.scheduler.nextFrame == nil)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(state.applied == inputs)
  }

  @Test func backpressureKeepsDemandUntilReadyThenRecovers() async {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    defer {
      runtime.scheduler.onFrame = nil
      runtime.reset()
    }
    var frames = 0
    runtime.scheduler.onFrame = { _ in frames += 1 }
    // This continuation is an input-drain barrier, not a timed sleep/yield guess.
    await withCheckedContinuation { continuation in
      runtime.dispatchInput {
        for _ in 0..<180 {
          runtime.scheduler.requestContent()
          clock.now += 0.023
        }
        continuation.resume()
      }
    }
    #expect(frames == 0)
    #expect(!runtime.scheduler.inputPending)
    #expect(!runtime.scheduler.isReady)
    #expect(runtime.scheduler.hasContentRequest)
    let requestedDeadline = runtime.scheduler.nextFrame?.deadline
    clock.now += 2  // Separate simulated compositor-not-ready interval.
    #expect(runtime.scheduler.nextFrame?.deadline == requestedDeadline)
    await withCheckedContinuation { continuation in
      runtime.scheduler.onFrame = { kind in
        frames += 1
        #expect(runtime.scheduler.isReady)
        _ = runtime.renderScheduled(kind, viewport: Size(width: 1, height: 1), onChange: {})
        runtime.scheduler.isReady = false
        continuation.resume()
      }
      runtime.scheduler.isReady = true
    }
    #expect(frames == 1)
    #expect(runtime.scheduler.nextFrame == nil)
  }
}
