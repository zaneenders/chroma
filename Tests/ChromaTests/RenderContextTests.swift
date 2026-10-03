import Testing

@testable import Chroma

@MainActor
struct BlockContextTests {

  @Test func contextBundlesInteractionState() {
    let interaction = Interaction()
    let context = BlockContext(interaction: interaction)

    #expect(context.interaction === interaction)
    #expect(context.selection === interaction.textSelection)
    #expect(context.fontMetrics == interaction.fontMetrics)
  }

  @Test func contextExposesPersistedPointerDragState() {
    let interaction = Interaction()
    let origin = Point(x: 10, y: 20)
    let current = Point(x: 30, y: 40)

    interaction.beginFrame(
      input: InputState(
        pointerPosition: origin, pointerPressPosition: origin,
        pointerDown: true, pointerPressed: true))
    interaction.endFrame()
    interaction.beginFrame(
      input: InputState(pointerPosition: current, pointerDown: true))

    let context = BlockContext(interaction: interaction)
    #expect(context.isPointerDragging)
    #expect(context.pointerDragOrigin == origin)
    #expect(context.pointerDragPosition == current)
  }

  @Test func contextFontMetricsWriteThroughToInteraction() {
    let interaction = Interaction()
    let context = BlockContext(interaction: interaction)

    var metrics = FontMetrics()
    metrics.glyphWidth = 10
    context.fontMetrics = metrics

    #expect(interaction.fontMetrics.glyphWidth == 10)
  }

  @Test func interactionOwnsFreshContextState() {
    let interaction = Interaction()
    #expect(interaction.fontMetrics == FontMetrics())
    #expect(interaction.textSelection.selectedText() == nil)
    #expect(!interaction.textSelection.isSelecting)
  }

  @Test func contextsOwnIndependentSelectionManagers() {
    let first = BlockContext()
    let second = BlockContext()

    #expect(first.selection !== second.selection)
  }

  @Test func blockEngineForwardsExplicitContext() {
    let interaction = Interaction()
    let context = BlockContext(interaction: interaction)
    let recorder = ContextRecorder()
    let block = ContextRecordingBlock(recorder: recorder)

    _ = BlockEngine.measure(block, proposal: Size(width: 20, height: 10), context: context)
    var drawList = DrawList()
    BlockEngine.draw(
      block,
      into: &drawList,
      in: Rect(x: 0, y: 0, width: 20, height: 10),
      context: context)

    #expect(recorder.measuredInteraction === interaction)
    #expect(recorder.drawnInteraction === interaction)
  }

  @Test func rendererContextWrapsItsInteraction() {
    let renderer = FakeRenderer()
    #expect(renderer.context.interaction === renderer.interaction)
    #expect(renderer.context.selection === renderer.interaction.textSelection)
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

private struct ContextRecordingBlock: PaintableBlock {
  func register(in rect: Rect, context: BlockContext) {}

  let recorder: ContextRecorder

  var focusRule: FocusRule { .standard }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    recorder.measuredInteraction = context.interaction
    return proposal
  }

  func paint(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    recorder.drawnInteraction = context.interaction
  }
}

@MainActor
private final class FakeRenderer: Host {
  let name = "Fake"
  var content: (any Block)?
  var frameObserver: FrameObserver?
  var onClose: (() -> Void)?
  let runtime = WindowRuntime()
  func run(title: String) {}
}
