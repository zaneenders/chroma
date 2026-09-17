@MainActor
public struct RenderContext {
  package var interaction: Interaction
  public var theme: ChromaTheme
  public var textScale: Float

  public var selection: TextSelectionManager { interaction.textSelection }

  public func setCopyTextProvider(_ provider: (@MainActor () -> String?)?) {
    interaction.onCopy = provider
  }

  public func setSelectAllHandler(_ handler: (@MainActor () -> Bool)?) {
    interaction.onSelectAll = handler
  }

  public var interactionMode: InteractionMode { interaction.mode }

  public var activeTextInput: WidgetID? {
    interaction.isTextEditing ? interaction.editingLeaf : nil
  }

  public var fontMetrics: FontMetrics {
    get { interaction.fontMetrics }
    nonmutating set { interaction.fontMetrics = newValue }
  }

  public var input: InputState { interaction.input }

  public var pointerDragOrigin: Point? { interaction.dragOrigin }

  public var pointerDragPosition: Point { interaction.dragCurrent }

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

  public func buttonState(
    id: WidgetID, in rect: Rect, role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    interaction.interactiveBehavior(id: id, rect: rect, role: role, action: action)
  }

  public func textInputState(
    id: WidgetID,
    in rect: Rect,
    text: @escaping @MainActor () -> String,
    onChange: @escaping @MainActor (String) -> Void,
    onSubmit: (@MainActor (String) -> Void)? = nil,
    onEndEditing: (@MainActor () -> CommandResult)? = nil,
    onTextEvent: (@MainActor (TextEditEvent, String) -> String?)? = nil,
    pointerOffset: (@MainActor (Point, Int?) -> Int)? = nil,
    verticalOffset: (@MainActor (Int, Int) -> Int)? = nil
  ) -> TextInputState {
    interaction.registerTextInput(
      id: id, rect: rect, text: text, onChange: onChange, onSubmit: onSubmit,
      onEndEditing: onEndEditing, onTextEvent: onTextEvent,
      pointerOffset: pointerOffset, verticalOffset: verticalOffset)
  }

  public func withFocusGroup<Result>(
    in rect: Rect,
    _ body: () throws -> Result
  ) rethrows -> Result {
    interaction.beginGroup(rect: rect)
    defer { interaction.endGroup() }
    return try body()
  }

  public func withInteractionClip<Result>(
    _ rect: Rect,
    _ body: () throws -> Result
  ) rethrows -> Result {
    interaction.pushClip(rect)
    defer { interaction.popClip() }
    return try body()
  }

  public func requestRedraw() {
    interaction.requestRedraw()
  }

  public func endEditing() {
    interaction.endEditing()
  }

  public func focus(_ id: WidgetID, editing: Bool = false) {
    interaction.focus(id, editing: editing)
  }
}

extension Renderer {
  package var context: RenderContext { RenderContext(interaction: interaction) }
}

extension RenderContext {
  public var caretVisible: Bool { interaction.caretClock.visible }
}
