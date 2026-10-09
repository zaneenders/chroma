import ChromaTesting
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
    let renderer = HeadlessHost()
    defer { renderer.close() }
    renderer.build = { buffer, context in
      var children: [LayoutNode] = []
      if model.primary {
        children.append(
          buffer.scrollView(
            ScrollView(build: { $0.text(Text("First"), context: $1) }), context: context.childScope(0)))
      }
      children.append(
        buffer.scrollView(
          ScrollView(build: { $0.text(Text("Second"), context: $1) }), context: context.childScope(1)))
      return buffer.stack(children, axis: .horizontal, context: context)
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
    let renderer = HeadlessHost()
    renderer.build = { $0.color(model.first, context: $1) }
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
    let renderer = HeadlessHost()
    renderer.build = { buffer, context in
      buffer.color(model.primary ? model.first : model.second, context: context)
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
    let renderer = HeadlessHost()
    @MainActor final class Condition {
      var primary = true
    }
    let condition = Condition()
    renderer.build = { buffer, context in
      buffer.color(condition.primary ? model.first : model.second, context: context)
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
    let renderer = HeadlessHost()
    renderer.build = { $0.color(model.first, context: $1) }
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    renderer.render()
    model.first = .yellow
    renderer.render()
    await drainChanges()
    #expect(redraws == 0)
    model.first = .black
    renderer.build = { $0.color(.white, context: $1) }
    await drainChanges()
    #expect(redraws == 0)
  }

  @Test func closeDiscardsQueuedCallbacks() async {
    let model = Model()
    let renderer = HeadlessHost()
    renderer.build = { $0.color(model.first, context: $1) }
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
    let renderer = HeadlessHost()
    renderer.build = { $0.color(model.first, context: $1) }
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
    let interaction = Interaction()
    let producer = FrameProducer()
    var requests = 0
    interaction.onRedrawRequested = { requests += 1 }
    _ = producer.render(
      build: { buffer, context in
        buffer.customLeaf(
          context: context, measure: { $0 }, register: { _ in },
          paint: { list, rect in
            list.fillRect(rect, color: model.first)
            model.first = .yellow
            context.requestRedraw()
          })
      },
      viewport: Size(width: 20, height: 20),
      input: InputState(), context: LayoutContext(interaction: interaction), onChange: {})
    #expect(requests == 1)
    #expect(interaction.consumeRedrawRequest())
    #expect(model.first == .yellow)
  }

  @Test func observationDoesNotRetainRenderer() async {
    let model = Model()
    weak var releasedRenderer: HeadlessHost?
    do {
      let renderer = HeadlessHost()
      releasedRenderer = renderer
      renderer.build = { $0.color(model.first, context: $1) }
      renderer.render()
    }
    #expect(releasedRenderer == nil)
    model.first = .yellow
    await drainChanges()
  }

  @Test func appRootReadsCurrentStateAndAsynchronousMutationRequestsRedraw() async throws {
    let model = Model()
    struct TestApp: App {
      let model: Model
      init() { model = Model() }
      init(model: Model) { self.model = model }
      func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
        buffer.color(model.first, context: context)
      }
    }
    let renderer = HeadlessHost()
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
