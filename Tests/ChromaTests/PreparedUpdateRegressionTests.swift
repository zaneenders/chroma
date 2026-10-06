import Observation
import Testing

@testable import Chroma

@MainActor
struct PreparedUpdateRegressionTests {
  private let viewport = Size(width: 160, height: 100)

  @Test func queuedActionsBeforeFirstPresentationNeverPaintPreActionState() {
    final class Model {
      var count = 0
      var painted: [Int] = []
    }
    struct Probe: PaintableBlock {
      let model: Model
      let value: Int
      var focusRule: FocusRule { .control }
      func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
      func register(in rect: Rect, context: BlockContext) {
        _ = context.buttonState(in: rect) { model.count = value + 1 }
      }
      func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) { model.painted.append(value) }
    }
    let model = Model()
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    runtime.content = DeferredBlock { Probe(model: model, value: model.count) }
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    for _ in 0..<3 { runtime.handleInput(InputState(commands: [.action(.activate)])) }
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(model.count == 3)
    #expect(model.painted == [3])
    #expect(runtime.scheduler.nextFrame == nil)
  }

  @Test func everyPointerUpdateUsesFreshGeometryAndReleasesPreparedNodes() {
    final class Model {
      var height: Float = 20
      var builds = 0
    }
    let model = Model()
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    runtime.content = DeferredBlock {
      model.builds += 1
      return VStack { Text("row").sizing(y: .fixed(model.height)) }
    }
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let before = model.builds
    for height: Float in [25, 30, 40] {
      model.height = height
      runtime.handleInput(InputState(pointerPosition: Point(x: 1, y: height - 1)))
      #expect(runtime.interaction.hoveredLeafID != nil)
      #expect(PipelineMetrics.snapshot.liveResolvedNodes == 0)
      #expect(PipelineMetrics.snapshot.paints == 0)
    }
    #expect(model.builds == before + 3)
  }

  @Observable final class Model {
    var first = "one"
    var second = "two"
  }

  @Test(ControlledObservationDelivery())
  func inputEvaluationRearmsDependenciesAndRejectsOlderQueuedResults() async {
    let model = Model()
    final class Choice { var first = true }
    let choice = Choice()
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    runtime.content = DeferredBlock { Text(choice.first ? model.first : model.second) }
    var redraws = 0
    let onChange: @MainActor @Sendable () -> Void = { redraws += 1 }
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: onChange)
    model.first = "stale"
    choice.first = false
    runtime.handleInput(InputState(pointerPosition: .zero))
    await drainObservationChanges()
    #expect(redraws == 0)
    await Task { @MainActor in model.second = "current" }.value
    await drainObservationChanges()
    #expect(redraws == 1)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: onChange)
    model.second = "next"
    await drainObservationChanges()
    #expect(redraws == 2)
  }

  @Test(arguments: [30.0, 60.0])
  func animationRequestsAndResizeUseTheSameCapAndReturnToIdle(rate: Double) throws {
    let clock = FrameSchedulerTests.Clock()
    let runtime = WindowRuntime(clock: { clock.now })
    defer { runtime.reset() }
    runtime.scheduler.setRefreshRates(minimum: rate, maximum: rate)
    runtime.content = Text("frame")
    #expect(runtime.scheduler.takeFrame() == .content)
    _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    #expect(runtime.scheduler.nextFrame == nil)
    runtime.scheduler.requestContent()
    runtime.scheduler.requestContent()
    let next = try #require(runtime.scheduler.nextFrame)
    #expect(next.deadline == clock.now + 1 / rate)
    #expect(runtime.scheduler.takeFrame() == nil)
    clock.now = next.deadline
    #expect(runtime.scheduler.takeFrame() == .content)
    _ = runtime.renderScheduled(.content, viewport: Size(width: 80, height: 50), onChange: {})
    #expect(runtime.interaction.viewport.size == Size(width: 80, height: 50))
    #expect(runtime.scheduler.nextFrame == nil)
  }
}

extension PreparedUpdateRegressionTests {
  @Test func reentrantInputWaitsForTheCurrentMutationToComplete() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    final class State {
      var events: [String] = []
      var value = 0
    }
    let state = State()
    runtime.content = DeferredBlock { [weak runtime] in
      let value = state.value
      return Text("commands").onCommand(.application("first")) { [weak runtime] in
        state.events.append("first-start")
        runtime?.handleInput(InputState(commands: [.application("second")]))
        state.value = 42
        state.events.append("first-end")
        return .handled
      }.onCommand(.application("second")) {
        state.events.append("second-\(value)")
        return .handled
      }
    }
    _ = runtime.renderScheduled(.content, viewport: Size(width: 100, height: 100), onChange: {})
    runtime.handleInput(InputState(commands: [.application("first")]))
    #expect(state.events == ["first-start", "first-end", "second-42"])
    _ = runtime.renderScheduled(.content, viewport: Size(width: 100, height: 100), onChange: {})
    #expect(state.events.count == 3)
  }

  @Test func variableRowsResolveOncePerOperationWithoutRetainingPreparedTrees() {
    final class State {
      var builds = 0
      var height: Float = 20
    }
    let state = State()
    let controller = ScrollViewController()
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    runtime.content = ScrollView(
      controller: controller,
      rows: [
        .init(
          id: 0,
          content: DeferredBlock {
            state.builds += 1
            return Text("row").sizing(y: .fixed(state.height))
          })
      ])
    _ = runtime.renderScheduled(.content, viewport: Size(width: 100, height: 10), onChange: {})
    let builds = state.builds
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    state.height = 40
    runtime.handleInput(InputState())
    #expect(state.builds == builds + 1)
    #expect(controller.rowGeometry.rowSizes.map(\.height) == [40])
    #expect(PipelineMetrics.snapshot.liveResolvedNodes == 0)
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 1)
    #expect(PipelineMetrics.snapshot.paints == 0)
  }
  @Test(arguments: [false, true])
  func batchedActionsResolveBetweenMutations(directPresentation: Bool) {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    final class State { var count = 0 }
    let state = State()
    runtime.content = DeferredBlock {
      let count = state.count
      return Button("increment") { state.count = count + 1 }
    }
    let viewport = Size(width: 100, height: 100)
    let input = InputState(commands: [.navigation(.nextFocus), .action(.activate), .action(.activate)])
    if directPresentation {
      _ = runtime.render(viewport: viewport, input: input, onChange: {})
    } else {
      runtime.handleInput(input)
      _ = runtime.renderScheduled(.content, viewport: viewport, onChange: {})
    }
    #expect(state.count == 2)
  }

  @Test func directPresentationResolvesAReplacementRootAfterDispatch() {
    let runtime = WindowRuntime()
    defer { runtime.reset() }
    runtime.content = Text("old").onCommand(.application("replace")) { [weak runtime] in
      runtime?.content = Text("new")
      return .handled
    }
    let list = runtime.render(
      viewport: Size(width: 100, height: 100), input: InputState(commands: [.application("replace")]), onChange: {})
    #expect(
      list.paintSnapshot.contains {
        if case .text(_, "new", _, _) = $0 { return true }
        return false
      })
    #expect(
      !list.paintSnapshot.contains {
        if case .text(_, "old", _, _) = $0 { return true }
        return false
      })
  }

}
