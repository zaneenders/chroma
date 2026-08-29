@MainActor
public struct RenderContext {
  package var interaction: Interaction
  public var theme: ChromaTheme
  public var textScale: Float

  public var selection: TextSelectionManager { interaction.textSelection }

  /// Installs a provider for text copied outside Chroma's built-in selectable
  /// text and editable controls. Platform clipboard backends consult it when an
  /// editable control does not own an active text selection.
  public func setCopyTextProvider(_ provider: (@MainActor () -> String?)?) {
    interaction.onCopy = provider
  }

  /// Installs a handler for Select All outside editable controls. Return `true`
  /// when the app selected its custom content, or `false` to fall back to
  /// Chroma's built-in selectable text.
  public func setSelectAllHandler(_ handler: (@MainActor () -> Bool)?) {
    interaction.onSelectAll = handler
  }

  /// The current input mode. Activating an editable control enters editing mode;
  /// ending editing or moving focus returns to movement mode.
  public var interactionMode: InteractionMode { interaction.mode }

  public var fontMetrics: FontMetrics {
    get { interaction.fontMetrics }
    nonmutating set { interaction.fontMetrics = newValue }
  }

  /// The translated input for the current frame.
  ///
  /// Custom primitives should inspect this snapshot instead of mutating engine state.
  public var input: InputState { interaction.input }

  /// The persisted origin of the active pointer drag. Unlike
  /// `input.pointerPressPosition`, this remains available after the press frame.
  public var pointerDragOrigin: Point? { interaction.dragOrigin }

  /// The latest pointer position captured for the active drag.
  public var pointerDragPosition: Point { interaction.dragCurrent }

  /// Whether a pointer drag is currently active.
  public var isPointerDragging: Bool { interaction.isDragging }

  public init(theme: ChromaTheme = .dark, textScale: Float = 1) {
    self.interaction = Interaction()
    self.theme = theme
    self.textScale = textScale
  }

  package init(interaction: Interaction, theme: ChromaTheme = .dark, textScale: Float = 1) {
    self.interaction = interaction
    self.theme = theme
    self.textScale = textScale
  }

  public func withTheme(_ theme: ChromaTheme) -> RenderContext {
    var copy = self
    copy.theme = theme
    return copy
  }

  public func withTextScale(_ scale: Float) -> RenderContext {
    var copy = self
    copy.textScale = scale
    return copy
  }

  /// Registers an interactive leaf and returns its state for the current frame.
  public func buttonState(
    id: WidgetID, in rect: Rect, role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    interaction.interactiveBehavior(id: id, rect: rect, role: role, action: action)
  }

  /// Registers an editable leaf and applies text input translated by the backend.
  ///
  /// `onEndEditing` can intercept an end-editing request. Return `.handled` to
  /// keep editing active, or `.ignored` to use the default behavior and leave
  /// editing mode.
  public func textInputState(
    id: WidgetID,
    in rect: Rect,
    text: String,
    onChange: (String) -> Void,
    onSubmit: ((String) -> Void)? = nil,
    onEndEditing: (() -> CommandResult)? = nil,
    pointerOffset: ((Point, Int?) -> Int)? = nil,
    verticalOffset: ((Int, Int) -> Int)? = nil
  ) -> TextInputState {
    interaction.textInputBehavior(
      id: id,
      rect: rect,
      text: text,
      onChange: onChange,
      onSubmit: onSubmit,
      onEndEditing: onEndEditing,
      pointerOffset: pointerOffset,
      verticalOffset: verticalOffset
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

  /// Invalidates the current view and asks the active renderer for another frame.
  /// Call this after asynchronous state changes that affect visible output.
  public func requestRedraw() {
    interaction.requestRedraw()
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
