@MainActor
public struct RenderContext {
  package var interaction: Interaction

  public var selection: TextSelectionManager { interaction.textSelection }

  public var fontMetrics: FontMetrics {
    get { interaction.fontMetrics }
    nonmutating set { interaction.fontMetrics = newValue }
  }

  /// The translated input for the current frame.
  ///
  /// Custom primitives should inspect this snapshot instead of mutating engine state.
  public var input: InputState { interaction.input }

  public init() {
    self.interaction = Interaction()
  }

  package init(interaction: Interaction) {
    self.interaction = interaction
  }

  /// Registers an interactive leaf and returns its state for the current frame.
  public func buttonState(id: WidgetID, in rect: Rect) -> ButtonState {
    interaction.interactiveBehavior(id: id, rect: rect)
  }

  /// Registers an editable leaf and applies text input translated by the backend.
  public func textInputState(
    id: WidgetID,
    in rect: Rect,
    text: String,
    onChange: (String) -> Void,
    onSubmit: ((String) -> Void)? = nil
  ) -> TextInputState {
    interaction.textInputBehavior(
      id: id,
      rect: rect,
      text: text,
      onChange: onChange,
      onSubmit: onSubmit
    )
  }

  /// Builds a scoped focus group for interactive children drawn by a custom primitive.
  public func withFocusGroup<Result>(
    _ axis: FocusAxis,
    in rect: Rect,
    _ body: () throws -> Result
  ) rethrows -> Result {
    interaction.beginGroup(axis, rect: rect)
    defer { interaction.endGroup() }
    return try body()
  }

  /// Restricts hit testing for interactive children to `rect` for the duration of `body`.
  /// Pair this with `DrawList.pushClip(_:)` when visual output must also be clipped.
  public func withInteractionClip<Result>(
    _ rect: Rect,
    _ body: () throws -> Result
  ) rethrows -> Result {
    interaction.pushClip(rect)
    defer { interaction.popClip() }
    return try body()
  }

  /// Moves keyboard focus to a registered interactive leaf.
  public func focus(_ id: WidgetID, editing: Bool = false) {
    interaction.focus(id, editing: editing)
  }

  /// Whether the focus group currently being drawn is selected as a group.
  public var isCurrentFocusGroupSelected: Bool {
    interaction.isCurrentGroupSelected
  }
}

extension Renderer {
  package var context: RenderContext { RenderContext(interaction: interaction) }
}
