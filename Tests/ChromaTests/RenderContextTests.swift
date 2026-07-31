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

  @Test func sharedSelectionManagerFollowsAmbientContext() {
    let first = Interaction()
    let second = Interaction()
    Interaction.current = first
    #expect(TextSelectionManager.shared === first.textSelection)
    Interaction.current = second
    #expect(TextSelectionManager.shared === second.textSelection)
    Interaction.current = Interaction()
  }

  @Test func rendererContextWrapsItsInteraction() {
    let renderer = FakeRenderer()
    #expect(renderer.context.interaction === renderer.interaction)
    #expect(renderer.context.selection === renderer.interaction.textSelection)
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
