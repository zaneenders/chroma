import Testing

@testable import Chroma

@MainActor
struct LayoutContextTests {

  @Test func contextBundlesInteractionState() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)

    #expect(context.interaction === interaction)
    #expect(context.fontMetrics == interaction.fontMetrics)
  }

  @Test func contextExposesPersistedPointerDragState() {
    let interaction = Interaction()
    let origin = Point(x: 10, y: 20)
    let current = Point(x: 30, y: 40)

    beginTestFrame(
      interaction,
      input: InputState(
        pointerPosition: origin, pointerPressPosition: origin,
        pointerDown: true, pointerPressed: true))
    interaction.endFrame()
    beginTestFrame(
      interaction,
      input: InputState(pointerPosition: current, pointerDown: true))

    let context = LayoutContext(interaction: interaction)
    #expect(context.isPointerDragging)
    #expect(context.pointerDragOrigin == origin)
    #expect(context.pointerDragPosition == current)
  }

  @Test func contextFontMetricsWriteThroughToInteraction() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)

    var metrics = FontMetrics()
    metrics.glyphWidth = 10
    context.fontMetrics = metrics

    #expect(interaction.fontMetrics.glyphWidth == 10)
  }

  @Test func interactionOwnsFreshContextState() {
    let interaction = Interaction()
    #expect(interaction.fontMetrics == FontMetrics())
    #expect(interaction.copyText() == nil)
    #expect(!interaction.isDragging)
  }

  @Test func contextsOwnIndependentInteractionState() {
    let first = LayoutContext()
    let second = LayoutContext()

    #expect(first.interaction !== second.interaction)
  }

  @Test func directLayoutForwardsExplicitContext() {
    let interaction = Interaction()
    let context = LayoutContext(interaction: interaction)
    let recorder = ContextRecorder()
    let build: LayoutBuilder = { buffer, context in
      buffer.customLeaf(
        context: context,
        measure: { proposal in
          recorder.measuredInteraction = context.interaction
          return proposal
        },
        register: { _ in }, paint: { _, _ in recorder.drawnInteraction = context.interaction })
    }

    _ = measureLayout(build, proposal: Size(width: 20, height: 10), context: context)
    context.interaction.beginFrame(input: InputState())
    var drawList = DrawList()
    do {
      var resolvedBuffer = LayoutBuffer()
      let resolved = build(&resolvedBuffer, context)
      resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 20, height: 10))
      resolvedBuffer.paint(resolved, into: &drawList, in: Rect(x: 0, y: 0, width: 20, height: 10))
    }

    context.interaction.endFrame()
    #expect(recorder.measuredInteraction === interaction)
    #expect(recorder.drawnInteraction === interaction)
  }

  @Test func rendererContextWrapsItsInteraction() {
    let renderer = FakeRenderer()
    #expect(renderer.context.interaction === renderer.interaction)
  }

  @Test func redrawInvalidationIsCoalescedUntilConsumed() {
    let interaction = Interaction()
    var invalidations = 0
    interaction.onRedrawRequested = { invalidations += 1 }

    interaction.requestRedraw()
    interaction.requestRedraw()
    #expect(invalidations == 1)
    #expect(interaction.consumeRedrawRequest())
    #expect(!interaction.consumeRedrawRequest())

    interaction.requestRedraw()
    #expect(invalidations == 2)
  }
}

@MainActor
private final class ContextRecorder {
  var measuredInteraction: Interaction?
  var drawnInteraction: Interaction?
}

@MainActor
private final class FakeRenderer: Host {
  let name = "Fake"
  var build: LayoutBuilder?
  var frameObserver: FrameObserver?
  var onClose: (() -> Void)?
  let runtime = WindowRuntime()
  func run(title: String) {}
}
