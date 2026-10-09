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

  private func leaf(
    capture: Capture, height: @escaping @MainActor () -> Float,
    action: (@MainActor () -> Void)? = nil, usesHoverStyle: Bool = false,
    into buffer: inout LayoutBuffer, context: LayoutContext
  ) -> LayoutNode {
    buffer.customLeaf(
      context: context, focusRule: action == nil ? .standard : .control,
      measure: { proposal in
        capture.measurements += 1
        let hoverHeight: Float = usesHoverStyle && context.hoverStyle != nil ? 10 : 0
        return Size(width: min(30, proposal.width), height: height() * context.textScale + hoverHeight)
      },
      register: { rect in
        capture.rects.append(rect)
        if let action { _ = context.buttonState(in: rect, action: action) }
      },
      paint: { _, _ in })
  }

  @discardableResult
  private func update(
    _ build: LayoutBuilder, context: LayoutContext = LayoutContext(),
    size: Size = Size(width: 100, height: 100), origin: Point = .zero
  ) -> Size {
    beginTestFrame(context.interaction, input: InputState())
    var resolvedBuffer = LayoutBuffer()
    let resolved = build(&resolvedBuffer, context)
    let measured = resolvedBuffer.sizeThatFits(resolved, size)
    resolvedBuffer.register(resolved, in: Rect(origin: origin, size: size))
    context.interaction.endFrame()
    return measured
  }

  @Test func geometryIsSharedWithinAnOperationAndRecomputedForTheNextUpdate() {
    let capture = Capture()
    var builds = 0
    let block: LayoutBuilder = { buffer, context in
      builds += 1
      let child = leaf(capture: capture, height: { capture.height }, into: &buffer, context: context.childScope(0))
      return buffer.stack([child], axis: .vertical, spacing: 3, context: context)
    }
    let context = LayoutContext()
    let proposal = Size(width: 100, height: 100)
    var resolvedBuffer = LayoutBuffer()
    let resolved = block(&resolvedBuffer, context)
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
    let block: LayoutBuilder = { buffer, context in
      let firstContext = context.childScope(0)
      let child = leaf(capture: first, height: { model.height }, into: &buffer, context: firstContext.childScope(0))
      let nested = buffer.stack([child], axis: .vertical, context: firstContext)
      let padded = buffer.padding(nested, 3, context: firstContext)
      let sibling = leaf(capture: second, height: { 12 }, into: &buffer, context: context.childScope(1))
      return buffer.stack([padded, sibling], axis: .vertical, spacing: 5, context: context)
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
    let block: LayoutBuilder = { buffer, context in
      var children = [leaf(capture: capture, height: { capture.height }, into: &buffer, context: context.childScope(0))]
      if model.extra {
        children.append(leaf(capture: capture, height: { 8 }, into: &buffer, context: context.childScope(1)))
      }
      return buffer.stack(children, axis: .vertical, context: context)
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
    host.build = { buffer, context in
      let current = capture.actions
      let child = leaf(
        capture: capture, height: { capture.height }, action: { capture.actions = current + 1 }, into: &buffer,
        context: context.childScope(0))
      return buffer.stack([child], axis: .vertical, context: context)
    }
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
    let block: LayoutBuilder = { buffer, context in
      leaf(capture: capture, height: { 12 }, into: &buffer, context: context)
    }
    #expect(update(block, size: Size(width: 10, height: 100)).width == 10)
    #expect(update(block, size: Size(width: 20, height: 100)).width == 20)
    let context = LayoutContext(theme: .dark.accentColor(.yellow), textScale: 2)
    #expect(update(block, context: context).height == 24)
    let replacement: LayoutBuilder = { buffer, context in
      let first = leaf(capture: capture, height: { 12 }, into: &buffer, context: context.childScope(0))
      let second = leaf(capture: capture, height: { 8 }, into: &buffer, context: context.childScope(1))
      return buffer.stack([first, second], axis: .vertical, context: context)
    }
    #expect(update(replacement).height == 20)
  }

  @Test func outerHoverEnvironmentUpdatesCustomLeafGeometry() {
    let capture = Capture()
    let block: LayoutBuilder = { buffer, context in
      leaf(capture: capture, height: { 12 }, usesHoverStyle: true, into: &buffer, context: context)
    }
    #expect(update(block).height == 12)
    var hovered = LayoutContext()
    hovered.hoverStyle = .standard
    #expect(update(block, context: hovered).height == 22)
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
        update { buffer, context in
          leaf(capture: capture, height: { model.height }, into: &buffer, context: context)
        }
      }
      #expect(retained == nil)
      #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 0)
    }
  }

  @Test func resetRejectsQueuedInvalidationAndReleasesCapturedModel() async {
    let producer = FrameProducer()
    let capture = Capture()
    let context = LayoutContext()
    var model: Model? = Model()
    weak let weakModel = model
    var oldRoot: LayoutBuilder? = { [model = model!] buffer, context in
      let child = leaf(capture: capture, height: { model.height }, into: &buffer, context: context.childScope(0))
      return buffer.stack([child], axis: .vertical, context: context)
    }
    var redraws = 0
    do {
      let build = oldRoot!
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
    let context = LayoutContext()
    let producer = FrameProducer()
    let viewport = Size(width: 100, height: 20)
    context.interaction.viewport = Rect(origin: .zero, size: viewport)
    let scroll = ScrollView(controller: controller) { buffer, context in
      leaf(capture: capture, height: { model.height }, into: &buffer, context: context)
    }
    let block: LayoutBuilder = { buffer, context in buffer.scrollView(scroll, context: context) }
    producer.refreshRegistrations(
      block, viewport: viewport, context: context)
    context.interaction.processInput(
      InputState(pointerPosition: Point(x: 5, y: 5), scrollDelta: Point(x: 0, y: -30)))
    context.interaction.finishInput()
    producer.refreshRegistrations(
      block, viewport: viewport, context: context)
    #expect(capture.rects.last?.minY == -30)
    #expect(context.interaction.tree?.hitTest(Point(x: 5, y: 5)) != nil)
    #expect(context.interaction.tree?.hitTest(Point(x: 5, y: 25)) == nil)
    model.height = 140
    producer.refreshRegistrations(
      block, viewport: viewport, context: context)
    #expect(capture.rects.last?.size.height == 140)

    let rowController = ScrollViewController()
    let rows = [
      ScrollView.Row(id: 0) { buffer, context in
        leaf(capture: capture, height: { model.height }, into: &buffer, context: context)
      }
    ]
    let rowBlock = ScrollView(controller: rowController, rows: rows)
    producer.refreshRegistrations(
      { buffer, context in buffer.scrollView(rowBlock, context: context) }, viewport: viewport, context: context)
    model.height = 160
    producer.refreshRegistrations(
      { buffer, context in buffer.scrollView(rowBlock, context: context) }, viewport: viewport, context: context)
    #expect(rowController.lazyStackCache.rowSizes.map(\.height) == [160])
  }
}
