import HeadlessBackend
import Observation
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct ObservationTests {
  @Observable
  final class Model {
    var primary = true
    var first = Color.white
    var second = Color.yellow
    var unused = 0
  }

  private func drainChanges() async {
    await drainObservationChanges()
  }

  @Test func removingScrollViewDoesNotInvalidateItsSibling() async {
    let model = Model()
    let renderer = HeadlessRenderer()
    defer { renderer.close() }
    renderer.content = DeferredBlock {
      HStack {
        if model.primary { ScrollView { Text("First") } }
        ScrollView { Text("Second") }
      }
    }
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    renderer.render()
    model.primary = false
    renderer.render()
    await drainChanges()
    #expect(redraws == 0)
  }

  @Test func tracksOnlyReadPropertiesAndRearmsAfterRendering() async {
    let model = Model()
    let renderer = HeadlessRenderer()
    renderer.content = DeferredBlock { model.first }
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    let initial = renderer.render()

    model.unused += 1
    await drainChanges()
    #expect(redraws == 0)

    model.first = .yellow
    model.first = .black
    await drainChanges()
    #expect(redraws == 1)
    let updated = renderer.render()
    #expect(updated != initial)

    model.first = .white
    await drainChanges()
    #expect(redraws == 2)
    #expect(renderer.render() == initial)
  }

  @Test func conditionalDependenciesAreReplaced() async {
    let model = Model()
    let renderer = HeadlessRenderer()
    renderer.content = DeferredBlock {
      if model.primary { model.first } else { model.second }
    }
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    renderer.render()
    model.primary = false
    await drainChanges()
    #expect(redraws == 1)
    renderer.render()
    model.first = .black
    await drainChanges()
    #expect(redraws == 1)
    model.second = .white
    await drainChanges()
    #expect(redraws == 2)
  }

  @Test func nonObservableConditionRefreshesDependenciesWithoutModelMutation() async {
    let model = Model()
    let renderer = HeadlessRenderer()
    @MainActor final class Condition {
      var primary = true
    }
    let condition = Condition()
    renderer.content = DeferredBlock {
      if condition.primary { model.first } else { model.second }
    }
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    renderer.render()
    condition.primary = false
    renderer.render()
    await drainChanges()
    #expect(redraws == 0)

    model.first = .black
    await drainChanges()
    #expect(redraws == 0)
    model.second = .white
    await drainChanges()
    #expect(redraws == 1)
  }

  @Test func newerFrameAndContentReplacementDiscardQueuedCallbacks() async {
    let model = Model()
    let renderer = HeadlessRenderer()
    renderer.content = DeferredBlock { model.first }
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    renderer.render()
    model.first = .yellow
    renderer.render()
    await drainChanges()
    #expect(redraws == 0)
    model.first = .black
    renderer.content = Color.white
    await drainChanges()
    #expect(redraws == 0)
  }

  @Test func closeDiscardsQueuedCallbacks() async {
    let model = Model()
    let renderer = HeadlessRenderer()
    renderer.content = DeferredBlock { model.first }
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    renderer.render()
    model.first = .yellow
    renderer.close()
    await drainChanges()
    #expect(redraws == 0)
  }

  @Test func observerReadsAreNotDependenciesAndWritesInvalidateAfterFrame() async {
    let model = Model()
    let renderer = HeadlessRenderer()
    renderer.content = DeferredBlock { model.first }
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    renderer.frameObserver = { _ in
      _ = model.unused
      model.first = .yellow
    }
    renderer.render()
    await drainChanges()
    #expect(redraws == 1)
    renderer.frameObserver = { _ in _ = model.unused }
    renderer.render()
    model.unused += 1
    await drainChanges()
    #expect(redraws == 1)
  }

  @Test func explicitRedrawSurvivesMutationDuringFirstDraw() {
    let model = Model()
    struct MutatingBlock: PrimitiveBlock {
      let model: Model
      var focusRule: FocusRule { .standard }
      func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }
      func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
        drawList.fillRect(rect, color: model.first)
        model.first = .yellow
        context.requestRedraw()
      }
    }
    let interaction = Interaction()
    let producer = FrameProducer()
    var requests = 0
    interaction.onRedrawRequested = { requests += 1 }
    _ = producer.render(
      content: MutatingBlock(model: model), viewport: Size(width: 20, height: 20),
      input: InputState(), context: RenderContext(interaction: interaction), onChange: {})
    #expect(requests == 1)
    #expect(interaction.consumeRedrawRequest())
    #expect(model.first == .yellow)
  }

  @Test func observationDoesNotRetainRenderer() async {
    let model = Model()
    weak var releasedRenderer: HeadlessRenderer?
    do {
      let renderer = HeadlessRenderer()
      releasedRenderer = renderer
      renderer.content = DeferredBlock { model.first }
      renderer.render()
    }
    #expect(releasedRenderer == nil)
    model.first = .yellow
    await drainChanges()
  }

  @Test func appRootIsDeferredAndAsynchronousMutationRequestsRedraw() async throws {
    let model = Model()
    struct TestApp: App {
      let model: Model
      init() { model = Model() }
      init(model: Model) { self.model = model }
      var body: some Block { model.first }
    }
    let renderer = HeadlessRenderer()
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    try TestApp(model: model).run(on: renderer)
    let initial = renderer.lastFrame
    await Task { @MainActor in model.first = .yellow }.value
    await drainChanges()
    #expect(redraws == 1)
    #expect(renderer.render() != initial)
  }
}
