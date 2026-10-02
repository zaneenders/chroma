import ChromaTesting
import Observation
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct RetainedLayoutTests {
  @Observable final class Model {
    var height: Float = 12
    var extra = false
  }

  final class Capture {
    var measurements = 0
    var rects: [Rect] = []
    var actions = 0
    var height: Float = 12
  }

  struct Leaf: PaintableBlock {
    let capture: Capture
    let height: @MainActor () -> Float
    var action: (@MainActor () -> Void)? = nil
    var usesHoverStyle = false
    var focusRule: FocusRule { action == nil ? .standard : .control }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      capture.measurements += 1
      let hoverHeight: Float = usesHoverStyle && context.hoverStyle != nil ? 10 : 0
      return Size(width: min(30, proposal.width), height: height() * context.textScale + hoverHeight)
    }
    func register(in rect: Rect, context: BlockContext) {
      capture.rects.append(rect)
      if let action { _ = context.buttonState(in: rect, action: action) }
    }
    func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      register(in: rect, context: context)
    }
    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {}
  }

  @discardableResult
  private func update(
    _ content: any Block, store: RetainedLayoutStore, context original: BlockContext = BlockContext(),
    size: Size = Size(width: 100, height: 100), origin: Point = .zero
  ) -> Size {
    var context = original
    context.retainedLayoutStore = store
    store.beginPass()
    defer { store.endPass() }
    context.interaction.beginFrame(input: InputState())
    let resolved = BlockEngine.resolve(content, context: context)
    let measured = resolved.sizeThatFits(size)
    resolved.register(in: Rect(origin: origin, size: size))
    context.interaction.endFrame()
    return measured
  }

  @Test func unchangedGeometryAndPlacementReuseAcrossFreshUpdates() {
    let cache = LayoutCache()
    let store = RetainedLayoutStore()
    let capture = Capture()
    var builds = 0
    let block = CachedLayout(cache) {
      builds += 1
      return VStack(spacing: 3) { Leaf(capture: capture, height: { 12 }) }
    }
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    update(block, store: store)
    let measured = capture.measurements
    PipelineMetrics.reset()
    update(block, store: store, origin: Point(x: 10, y: 20))
    #expect(builds == 2)
    #expect(capture.measurements == measured)
    #expect(capture.rects.last?.origin == Point(x: 10, y: 20))
    #expect(PipelineMetrics.snapshot.retainedMeasurementHits > 0)
    #expect(PipelineMetrics.snapshot.retainedPlacementHits > 0)
    #expect(PipelineMetrics.snapshot.paints == 0)
    #expect(PipelineMetrics.snapshot.liveRetainedNodes > 0)
    store.reset()
    #expect(PipelineMetrics.snapshot.liveRetainedNodes == 0)
  }

  @Test func observedLeafChangeImmediatelyRepositionsParentAndSibling() {
    let model = Model()
    let first = Capture()
    let second = Capture()
    let firstCache = LayoutCache()
    let secondCache = LayoutCache()
    let store = RetainedLayoutStore()
    let block = VStack(spacing: 5) {
      CachedLayout(firstCache) {
        VStack { Leaf(capture: first, height: { model.height }) }.padding(3)
      }
      CachedLayout(secondCache) { Leaf(capture: second, height: { 12 }) }
    }
    update(block, store: store)
    #expect(second.rects.last?.minY == 23)
    let unrelatedMeasures = second.measurements
    model.height = 32
    // Do not deliver any queued observation callback before this next update.
    update(block, store: store)
    #expect(second.rects.last?.minY == 43)
    #expect(second.measurements == unrelatedMeasures)
  }

  @Test func observedBuilderStructureAndNestedExplicitInvalidationPropagate() {
    let model = Model()
    let capture = Capture()
    let outer = LayoutCache()
    var inner = LayoutCache()
    let store = RetainedLayoutStore()
    let block = CachedLayout(outer) {
      VStack(spacing: 0) {
        CachedLayout(inner) { Leaf(capture: capture, height: { capture.height }) }
        if model.extra { Leaf(capture: capture, height: { 8 }) }
      }
    }
    #expect(update(block, store: store).height == 12)
    capture.height = 24
    inner.invalidate()
    #expect(update(block, store: store).height == 24)
    inner = LayoutCache()
    capture.height = 28
    #expect(update(block, store: store).height == 28)
    model.extra = true
    #expect(update(block, store: store).height == 36)
  }

  @Test func explicitInvalidationIsRequiredForUnobservedGeometryButNotActions() {
    let capture = Capture()
    let cache = LayoutCache()
    let host = HeadlessHost(size: Size(width: 100, height: 100))
    defer { host.close() }
    host.content = CachedLayout(cache) {
      let current = capture.actions
      return VStack {
        Leaf(capture: capture, height: { capture.height }, action: { capture.actions = current + 1 })
      }
    }
    host.render()
    let measured = capture.measurements
    host.sendInput(InputState(commands: [.navigation(.down)]))
    host.sendInput(InputState(commands: [.action(.activate)]))
    host.sendInput(InputState(commands: [.action(.activate)]))
    #expect(capture.actions == 2)
    #expect(capture.measurements == measured)
    capture.height = 28
    cache.invalidate()
    host.sendInput(InputState(commands: [.navigation(.down)]))
    #expect(capture.measurements > measured)
  }

  @Test func proposalsEnvironmentAndStructureInvalidateRetainedGeometry() {
    let cache = LayoutCache()
    let capture = Capture()
    let store = RetainedLayoutStore()
    let block = CachedLayout(cache) { Leaf(capture: capture, height: { 12 }) }
    #expect(update(block, store: store, size: Size(width: 10, height: 100)).width == 10)
    #expect(update(block, store: store, size: Size(width: 20, height: 100)).width == 20)
    let context = BlockContext(theme: .dark.accentColor(.yellow), textScale: 2)
    #expect(update(block, store: store, context: context).height == 24)
    let replacement = CachedLayout(cache) {
      VStack(spacing: 0) {
        Leaf(capture: capture, height: { 12 })
        Leaf(capture: capture, height: { 8 })
      }
    }
    #expect(update(replacement, store: store).height == 20)
  }

  @Test func outerHoverEnvironmentInvalidatesCustomLeafGeometry() {
    let cache = LayoutCache()
    let capture = Capture()
    let store = RetainedLayoutStore()
    let block = CachedLayout(cache) { Leaf(capture: capture, height: { 12 }, usesHoverStyle: true) }
    #expect(update(block, store: store).height == 12)
    #expect(update(block.hover(.standard), store: store).height == 22)
    #expect(update(block, store: store).height == 12)
  }

  @Test func removingBoundariesReleasesNodesAndSubscriptions() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let cache = LayoutCache()
    let model = Model()
    let capture = Capture()
    let store = RetainedLayoutStore()
    for _ in 0..<20 {
      update(CachedLayout(cache) { Leaf(capture: capture, height: { model.height }) }, store: store)
    }
    #expect(store.count == 1)
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 3)
    update(EmptyBlock(), store: store)
    #expect(store.count == 0)
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 0)
    #expect(PipelineMetrics.snapshot.liveRetainedNodes == 0)
  }

  @Test func resetRejectsQueuedInvalidationAndReleasesCapturedModel() async {
    let producer = FrameProducer()
    let capture = Capture()
    let context = BlockContext()
    let cache = LayoutCache()
    var model: Model? = Model()
    weak let weakModel = model
    var oldRoot: (any Block)? = CachedLayout(cache) { [model = model!] in
      VStack { Leaf(capture: capture, height: { model.height }) }
    }
    var redraws = 0
    _ = producer.render(
      content: oldRoot, viewport: Size(width: 100, height: 100), input: InputState(),
      context: context, onChange: { redraws += 1 })
    model?.height = 22
    producer.reset()
    oldRoot = nil
    model = nil
    await drainObservationChanges()
    #expect(redraws == 0)
    #expect(weakModel == nil)
  }

  @Test func retainedScrollUpdatesOffsetsClippingAndVariableRowHeights() {
    let cache = LayoutCache()
    let model = Model()
    model.height = 100
    let capture = Capture()
    let controller = ScrollViewController()
    let context = BlockContext()
    let producer = FrameProducer()
    let viewport = Size(width: 100, height: 20)
    context.interaction.viewport = Rect(origin: .zero, size: viewport)
    let block = CachedLayout(cache) {
      ScrollView(controller: controller) { Leaf(capture: capture, height: { model.height }) }
    }
    producer.refreshRegistrations(block, viewport: viewport, context: context)
    let measurements = capture.measurements
    context.interaction.processInput(
      InputState(pointerPosition: Point(x: 5, y: 5), scrollDelta: Point(x: 0, y: -30)))
    context.interaction.finishInput()
    producer.refreshRegistrations(block, viewport: viewport, context: context)
    #expect(capture.rects.last?.minY == -30)
    // Scroll content is resolved during registration and remains conservatively uncached.
    #expect(capture.measurements == measurements + 2)
    #expect(context.interaction.tree?.hitTest(Point(x: 5, y: 5)) != nil)
    #expect(context.interaction.tree?.hitTest(Point(x: 5, y: 25)) == nil)
    model.height = 140
    producer.refreshRegistrations(block, viewport: viewport, context: context)
    #expect(capture.rects.last?.size.height == 140)

    let rowController = ScrollViewController()
    let rows = [ScrollView.Row(id: 0, content: Leaf(capture: capture, height: { model.height }))]
    let rowBlock = CachedLayout(LayoutCache()) { ScrollView(controller: rowController, rows: rows) }
    producer.refreshRegistrations(rowBlock, viewport: viewport, context: context)
    model.height = 160
    producer.refreshRegistrations(rowBlock, viewport: viewport, context: context)
    #expect(rowController.lazyStackCache.rowSizes.map(\.height) == [160])
  }

  @Test func proposalStorageIsBoundedAndNewCacheTokenNeverAdoptsOldGeometry() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let store = RetainedLayoutStore()
    let cache = LayoutCache()
    let capture = Capture()
    for width in 1...100 {
      update(
        CachedLayout(cache) { Leaf(capture: capture, height: { 12 }) }, store: store,
        size: Size(width: Float(width), height: 100))
    }
    #expect(store.nodeCount == 2)  // Builder tuple plus leaf.
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions <= 2 * RetainedLayoutEntry.proposalLimit + 1)
    let measurements = capture.measurements
    let block = CachedLayout(cache) { Leaf(capture: capture, height: { 12 }) }
    update(block, store: store, size: Size(width: 100, height: 100))
    #expect(capture.measurements == measurements + 1, "Eviction retires the whole boundary epoch")
    update(block, store: store, size: Size(width: 100, height: 100))
    #expect(capture.measurements == measurements + 1, "Rearmed unchanged geometry reuses measurement")
    update(block, store: store, size: Size(width: 1, height: 100))
    #expect(capture.measurements == measurements + 2, "The oldest proposal was evicted")
    let replacement = LayoutCache()
    #expect(update(CachedLayout(replacement) { Leaf(capture: capture, height: { 25 }) }, store: store).height == 25)
    #expect(store.count == 1)
  }

  @Test func oversizedBoundariesFallBackAndWindowBoundaryStorageIsBounded() {
    let cache = LayoutCache()
    let capture = Capture()
    let store = RetainedLayoutStore()
    let oversized = CachedLayout(cache) {
      TupleBlock(
        children: (0...RetainedLayoutEntry.nodeLimit).map { _ in
          Leaf(capture: capture, height: { capture.height })
        })
    }
    #expect(update(oversized, store: store).height == 12)
    capture.height = 24  // Overflow must be conservative even without invalidation.
    #expect(update(oversized, store: store).height == 24)
    #expect(store.nodeCount == 0)
    store.reset()
    let boundaries = (0...RetainedLayoutStore.boundaryLimit).map { _ in
      CachedLayout(LayoutCache()) { Leaf(capture: capture, height: { 12 }) }
    }
    update(TupleBlock(children: boundaries), store: store)
    #expect(store.count == RetainedLayoutStore.boundaryLimit)
    update(EmptyBlock(), store: store)
    #expect(store.count == 0)
  }

}
