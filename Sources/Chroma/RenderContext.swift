@MainActor
public struct RenderContext {
  public var interaction: Interaction

  public var selection: TextSelectionManager { interaction.textSelection }

  public var fontMetrics: FontMetrics {
    get { interaction.fontMetrics }
    nonmutating set { interaction.fontMetrics = newValue }
  }

  public init(interaction: Interaction = Interaction()) {
    self.interaction = interaction
  }
}

extension Renderer {
  public var context: RenderContext { RenderContext(interaction: interaction) }
}
