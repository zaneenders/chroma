import Testing

@testable import Chroma

@MainActor
struct RenderContextTests {

  @Test func contextBundlesInteractionState() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)

    #expect(context.interaction === interaction)
    #expect(context.selection === interaction.textSelection)
    #expect(context.fontMetrics == interaction.fontMetrics)
  }

  @Test func contextFontMetricsWriteThroughToInteraction() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)

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
    let first = RenderContext()
    let second = RenderContext()

    #expect(first.selection !== second.selection)
  }

  @Test func blockEngineForwardsExplicitContext() {
    let interaction = Interaction()
    let context = RenderContext(interaction: interaction)
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
}

@MainActor
private final class ContextRecorder {
  var measuredInteraction: Interaction?
  var drawnInteraction: Interaction?
}

private struct ContextRecordingBlock: PrimitiveBlock {
  let recorder: ContextRecorder

  func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    recorder.measuredInteraction = context.interaction
    return proposal
  }

  func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    recorder.drawnInteraction = context.interaction
  }
}

@MainActor
private final class FakeRenderer: Renderer {
  let name = "Fake"
  var content: (any Block)?
  var onClose: (() -> Void)?
  let interaction = Interaction()
  func run(title: String) {}
}
