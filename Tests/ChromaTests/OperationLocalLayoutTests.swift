import ChromaTesting
import Observation
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct OperationLocalLayoutTests {
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

  struct Leaf: Block {

    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        expandsHorizontally: false, expandsVertically: false,
        measure: { sizeThatFits($0, context: context) },
        register: { register(in: $0, context: context) },
        paint: { paint(into: &$0, in: $1, context: context) })
    }

    let capture: Capture
    let height: @MainActor () -> Float
    var action: (@MainActor () -> Void)? = nil
    var usesHoverStyle = false
    var focusRule: FocusRule { action == nil ? .standard : .control }
    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      capture.measurements += 1
      let hoverHeight: Float = usesHoverStyle && context.hoverStyle != nil ? 10 : 0
      return Size(width: min(30, proposal.width), height: height() * context.textScale + hoverHeight)
    }
    @MainActor func register(in rect: Rect, context: BlockContext) {
      capture.rects.append(rect)
      if let action { _ = context.buttonState(in: rect, action: action) }
    }

    @MainActor func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {}
  }

  @discardableResult
  private func update(
    _ content: any Block, context: BlockContext = BlockContext(),
    size: Size = Size(width: 100, height: 100), origin: Point = .zero
  ) -> Size {
    beginTestFrame(context.interaction, input: InputState())
    var resolvedBuffer = LayoutBuffer()
    let resolved = resolvedBuffer.emit(content, context: context)
    let measured = resolvedBuffer.sizeThatFits(resolved, size)
    resolvedBuffer.register(resolved, in: Rect(origin: origin, size: size))
    context.interaction.endFrame()
    return measured
  }

  @Test func geometryIsSharedWithinAnOperationAndRecomputedForTheNextUpdate() {
    let capture = Capture()
    var builds = 0
    let block = DeferredBlock {
      builds += 1
      return VStack(spacing: 3) { Leaf(capture: capture, height: { capture.height }) }
    }
    let context = BlockContext()
    let proposal = Size(width: 100, height: 100)
    var resolvedBuffer = LayoutBuffer()
    let resolved = resolvedBuffer.emit(block, context: context)
    #expect(resolvedBuffer.sizeThatFits(resolved, proposal).height == 12)
    let measured = capture.measurements
    #expect(resolvedBuffer.sizeThatFits(resolved, proposal).height == 12)
    beginTestFrame(context.interaction, input: InputState())
    resolvedBuffer.register(resolved, in: Rect(origin: .zero, size: proposal))
    context.interaction.endFrame()
    var list = DrawList()
    resolvedBuffer.paint(resolved, into: &list, in: Rect(origin: .zero, size: proposal))
    #expect(builds == 1)
    #expect(capture.measurements == measured)

    capture.height = 28
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    #expect(update(block, context: context, origin: Point(x: 10, y: 20)).height == 28)
    #expect(builds == 2)
    #expect(capture.measurements > measured)
    #expect(capture.rects.last == Rect(x: 10, y: 20, width: 30, height: 28))
    #expect(PipelineMetrics.snapshot.paints == 0)
  }

  @Test func observedLeafChangeImmediatelyRepositionsParentAndSibling() {
    let model = Model()
    let first = Capture()
    let second = Capture()
    let block = VStack(spacing: 5) {
      VStack { Leaf(capture: first, height: { model.height }) }.padding(3)
      Leaf(capture: second, height: { 12 })
    }
    update(block)
    #expect(second.rects.last?.minY == 23)
    model.height = 32
    // Do not deliver any queued observation callback before this next update.
    update(block)
    #expect(second.rects.last?.minY == 43)
  }

  @Test func builderStructureAndUnobservedGeometryRefreshWithoutInvalidation() {
    let model = Model()
    let capture = Capture()
    let block = DeferredBlock {
      VStack(spacing: 0) {
        Leaf(capture: capture, height: { capture.height })
        if model.extra { Leaf(capture: capture, height: { 8 }) }
      }
    }
    #expect(update(block).height == 12)
    capture.height = 24
    #expect(update(block).height == 24)
    model.extra = true
    #expect(update(block).height == 32)
  }

  @Test func actionsAndUnobservedGeometryRefreshBeforeEachInput() {
    let capture = Capture()
    let host = HeadlessHost(size: Size(width: 100, height: 100))
    defer { host.close() }
    host.setContent(
      DeferredBlock {
        let current = capture.actions
        return VStack {
          Leaf(capture: capture, height: { capture.height }, action: { capture.actions = current + 1 })
        }
      })
    host.render()
    host.sendInput(InputState(commands: [.navigation(.down)]))
    host.sendInput(InputState(commands: [.action(.activate)]))
    host.sendInput(InputState(commands: [.action(.activate)]))
    #expect(capture.actions == 2)
    capture.height = 28
    host.sendInput(InputState(commands: [.navigation(.down)]))
    #expect(capture.rects.last?.size.height == 28)
  }

  @Test func proposalsEnvironmentAndStructureUseCurrentGeometry() {
    let capture = Capture()
    let block = Leaf(capture: capture, height: { 12 })
    #expect(update(block, size: Size(width: 10, height: 100)).width == 10)
    #expect(update(block, size: Size(width: 20, height: 100)).width == 20)
    let context = BlockContext(theme: .dark.accentColor(.yellow), textScale: 2)
    #expect(update(block, context: context).height == 24)
    let replacement = VStack(spacing: 0) {
      Leaf(capture: capture, height: { 12 })
      Leaf(capture: capture, height: { 8 })
    }
    #expect(update(replacement).height == 20)
  }

  @Test func outerHoverEnvironmentUpdatesCustomLeafGeometry() {
    let capture = Capture()
    let block = Leaf(capture: capture, height: { 12 }, usesHoverStyle: true)
    #expect(update(block).height == 12)
    #expect(update(block.hover(.standard)).height == 22)
    #expect(update(block).height == 12)
  }

  @Test func updatesReleasePreparedContentWithoutAddingGeometrySubscriptions() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let model = Model()
    for _ in 0..<20 {
      weak var retained: Capture?
      do {
        let capture = Capture()
        retained = capture
        update(Leaf(capture: capture, height: { model.height }))
      }
      #expect(retained == nil)
      #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 0)
    }
  }

  @Test func resetRejectsQueuedInvalidationAndReleasesCapturedModel() async {
    let producer = FrameProducer()
    let capture = Capture()
    let context = BlockContext()
    var model: Model? = Model()
    weak let weakModel = model
    var oldRoot: (any Block)? = DeferredBlock { [model = model!] in
      VStack { Leaf(capture: capture, height: { model.height }) }
    }
    var redraws = 0
    do {
      let root = oldRoot!
      let build: LayoutBuilder = { buffer, context in buffer.emit(root, context: context) }
      _ = producer.render(
        build: build, viewport: Size(width: 100, height: 100), input: InputState(),
        context: context, onChange: { redraws += 1 })
    }
    model?.height = 22
    producer.reset()
    oldRoot = nil
    model = nil
    await drainObservationChanges()
    #expect(redraws == 0)
    #expect(weakModel == nil)
  }

  @Test func scrollUpdatesOffsetsClippingAndVariableRowHeights() {
    let model = Model()
    model.height = 100
    let capture = Capture()
    let controller = ScrollViewController()
    let context = BlockContext()
    let producer = FrameProducer()
    let viewport = Size(width: 100, height: 20)
    context.interaction.viewport = Rect(origin: .zero, size: viewport)
    let block = ScrollView(controller: controller) { Leaf(capture: capture, height: { model.height }) }
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(block, context: context) }, viewport: viewport, context: context)
    context.interaction.processInput(
      InputState(pointerPosition: Point(x: 5, y: 5), scrollDelta: Point(x: 0, y: -30)))
    context.interaction.finishInput()
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(block, context: context) }, viewport: viewport, context: context)
    #expect(capture.rects.last?.minY == -30)
    #expect(context.interaction.tree?.hitTest(Point(x: 5, y: 5)) != nil)
    #expect(context.interaction.tree?.hitTest(Point(x: 5, y: 25)) == nil)
    model.height = 140
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(block, context: context) }, viewport: viewport, context: context)
    #expect(capture.rects.last?.size.height == 140)

    let rowController = ScrollViewController()
    let rows = [ScrollView.Row(id: 0, content: Leaf(capture: capture, height: { model.height }))]
    let rowBlock = ScrollView(controller: rowController, rows: rows)
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(rowBlock, context: context) }, viewport: viewport, context: context)
    model.height = 160
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(rowBlock, context: context) }, viewport: viewport, context: context)
    #expect(rowController.lazyStackCache.rowSizes.map(\.height) == [160])
  }
}
