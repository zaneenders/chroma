@MainActor
public struct RenderContext {
  var structuralPath = StructuralPath()
  var widgetID: WidgetID { WidgetID(path: structuralPath) }
  var backgroundDepth = 0
  var focusTargets: [FocusTarget] = []

  /// Set while drawing content that a registered leaf already owns — Interactive content,
  /// decorative backgrounds — so it does not register default focus leaves of its own.
  var focusLeafClaimed = false

  /// Overrides the highlight drawn for default focus leaves; `nil` uses the theme standard.
  public var hoverStyle: HoverStyle?

  /// Use distinct, stable slots for custom-container children in both measurement and drawing.
  /// Slots describe source structure, not visible-child indices or draw order.
  public func childScope(_ slot: Int) -> RenderContext {
    scoped([.slot(slot)])
  }

  var backgroundContentContext: RenderContext {
    var copy = self
    copy.backgroundDepth += 1
    return copy
  }

  var backgroundContext: RenderContext {
    var copy = scoped([.background(backgroundDepth)])
    copy.focusTargets = []
    copy.focusLeafClaimed = true
    return copy
  }

  func scoped(_ segments: [StructuralPath.Segment]) -> RenderContext {
    var copy = self
    copy.structuralPath.segments += segments
    copy.backgroundDepth = 0
    return copy
  }

  func childContext(for child: any Block, at index: Int) -> RenderContext {
    child is ScopedBlock ? self : scoped([.slot(index)])
  }

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

  var activeTextInput: WidgetID? {
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

  func buttonState(
    id: WidgetID, in rect: Rect, role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    interaction.registerFocusTargets(focusTargets, id: id)
    return interaction.interactiveBehavior(id: id, rect: rect, role: role, action: action)
  }

  public func buttonState(
    in rect: Rect, role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    let id = widgetID
    interaction.registerFocusTargets(focusTargets, id: id)
    return interaction.interactiveBehavior(id: id, rect: rect, role: role, action: action)
  }

  /// Registers a focus leaf for content a custom primitive paints itself and draws the
  /// standard highlight over it: keyboard focus, pointer hover, and press all tint the
  /// leaf like default content. Call after drawing the leaf's content so the highlight
  /// layers over it. `.hover(.none)` removes the leaves; `.hover(.tint)` recolors the
  /// highlight. Controls that paint their own feedback use `buttonState` instead.
  @discardableResult
  public func focusable(
    in rect: Rect, into drawList: inout DrawList,
    role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    guard hoverStyle != HoverStyle.none else {
      return ButtonState(hovered: false, held: false, clicked: false)
    }
    let id = widgetID
    let state = buttonState(in: rect, role: role, action: action)
    BlockEngine.drawHighlight(for: id, into: &drawList, in: rect, context: self)
    return state
  }

  func textInputState(
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
    interaction.registerFocusTargets(focusTargets, id: id)
    return interaction.registerTextInput(
      id: id, rect: rect, text: text, onChange: onChange, onSubmit: onSubmit,
      onEndEditing: onEndEditing, onTextEvent: onTextEvent,
      pointerOffset: pointerOffset, verticalOffset: verticalOffset)
  }

  public func textInputState(
    in rect: Rect,
    text: @escaping @MainActor () -> String,
    onChange: @escaping @MainActor (String) -> Void,
    onSubmit: (@MainActor (String) -> Void)? = nil,
    onEndEditing: (@MainActor () -> CommandResult)? = nil,
    onTextEvent: (@MainActor (TextEditEvent, String) -> String?)? = nil,
    pointerOffset: (@MainActor (Point, Int?) -> Int)? = nil,
    verticalOffset: (@MainActor (Int, Int) -> Int)? = nil
  ) -> TextInputState {
    let id = widgetID
    interaction.registerFocusTargets(focusTargets, id: id)
    return interaction.registerTextInput(
      id: id, rect: rect, text: text, onChange: onChange, onSubmit: onSubmit,
      onEndEditing: onEndEditing, onTextEvent: onTextEvent,
      pointerOffset: pointerOffset, verticalOffset: verticalOffset)
  }

  /// Scopes focusable content drawn in `rect` into one group of the focus tree.
  ///
  /// `axis` declares the direction siblings inside the closure are laid out in, so custom containers
  /// navigate like the built-in stacks. Nested groups declare their own axis; `nil` inherits movement
  /// from the nearest enclosing group with a matching axis.
  public func withFocusGroup<Result>(
    in rect: Rect,
    axis: FocusGroupAxis? = nil,
    _ body: () throws -> Result
  ) rethrows -> Result {
    interaction.beginGroup(rect: rect, axis: axis)
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

  func focus(_ id: WidgetID, editing: Bool = false) {
    interaction.focus(id, editing: editing)
  }
}

extension Renderer {
  package var context: RenderContext { RenderContext(interaction: interaction) }
}

extension RenderContext {
  public var caretVisible: Bool { interaction.caretClock.visible }
}
