@MainActor
public struct BlockContext {
  var structuralPath = StructuralPath()
  var widgetID: WidgetID { WidgetID(path: structuralPath) }
  var backgroundDepth = 0
  var focusTargets: [FocusTarget] = []

  var focusLeafClaimed = false
  var navigationIgnored = false

  public var hoverStyle: HoverStyle?

  public func childScope(_ slot: Int) -> BlockContext {
    scoped([.slot(slot)])
  }

  var backgroundContentContext: BlockContext {
    var copy = self
    copy.backgroundDepth += 1
    return copy
  }

  var backgroundContext: BlockContext {
    var copy = scoped([.background(backgroundDepth)])
    copy.focusTargets = []
    copy.focusLeafClaimed = true
    return copy
  }

  func scoped(_ segments: [StructuralPath.Segment]) -> BlockContext {
    var copy = self
    copy.structuralPath.segments += segments
    copy.backgroundDepth = 0
    return copy
  }

  func childContext(for child: any Block, at index: Int) -> BlockContext {
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

  public var navigationBreadcrumb: [String] {
    guard let root = interaction.navigation else { return ["Window"] }
    return ["Window"]
      + interaction.navigationPath.indices.compactMap { depth in
        root.node(at: Array(interaction.navigationPath.prefix(depth + 1)))?.name
      }
  }

  public var navigationSelectionIsGroup: Bool {
    interaction.navigation?.node(at: interaction.navigationPath)?.isGroup ?? true
  }

  public var isSelectingText: Bool { interaction.editingLeaf != nil && !interaction.isTextEditing }

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

  public func withTheme(_ theme: ChromaTheme) -> BlockContext {
    var copy = self
    copy.theme = theme
    return copy
  }

  func buttonState(
    id: WidgetID, in rect: Rect, role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    interaction.registerFocusTargets(focusTargets, id: id)
    return interaction.interactiveBehavior(
      id: id, rect: rect, role: role, action: action, navigationIgnored: navigationIgnored)
  }

  public func buttonState(
    in rect: Rect, role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    let id = widgetID
    interaction.registerFocusTargets(focusTargets, id: id)
    return interaction.interactiveBehavior(
      id: id, rect: rect, role: role, action: action, navigationIgnored: navigationIgnored)
  }

  /// Registers a focus leaf and current behavior without emitting a visual highlight.
  @discardableResult
  public func registerFocusable(
    in rect: Rect, role: ActionRole = .normal, action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    guard !navigationIgnored else {
      return ButtonState(hovered: false, held: false, clicked: false)
    }
    return buttonState(in: rect, role: role, action: action)
  }

  @discardableResult
  public func focusable(
    in rect: Rect, into drawList: inout DrawList,
    role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    guard !navigationIgnored else {
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
    verticalOffset: (@MainActor (Int, Int) -> Int)? = nil,
    submitInsertsNewline: Bool = false
  ) -> TextInputState {
    interaction.registerFocusTargets(focusTargets, id: id)
    return interaction.registerTextInput(
      id: id, rect: rect, text: text, onChange: onChange, onSubmit: onSubmit,
      onEndEditing: onEndEditing, onTextEvent: onTextEvent,
      pointerOffset: pointerOffset, verticalOffset: verticalOffset, navigationIgnored: navigationIgnored,
      submitInsertsNewline: submitInsertsNewline)
  }

  public func textInputState(
    in rect: Rect,
    text: @escaping @MainActor () -> String,
    onChange: @escaping @MainActor (String) -> Void,
    onSubmit: (@MainActor (String) -> Void)? = nil,
    onEndEditing: (@MainActor () -> CommandResult)? = nil,
    onTextEvent: (@MainActor (TextEditEvent, String) -> String?)? = nil,
    pointerOffset: (@MainActor (Point, Int?) -> Int)? = nil,
    verticalOffset: (@MainActor (Int, Int) -> Int)? = nil,
    submitInsertsNewline: Bool = false
  ) -> TextInputState {
    let id = widgetID
    interaction.registerFocusTargets(focusTargets, id: id)
    return interaction.registerTextInput(
      id: id, rect: rect, text: text, onChange: onChange, onSubmit: onSubmit,
      onEndEditing: onEndEditing, onTextEvent: onTextEvent,
      pointerOffset: pointerOffset, verticalOffset: verticalOffset, navigationIgnored: navigationIgnored,
      submitInsertsNewline: submitInsertsNewline)
  }

  public func textSelectionState(
    in rect: Rect,
    text: @escaping @MainActor () -> String,
    pointerOffset: (@MainActor (Point, Int?) -> Int)? = nil,
    verticalOffset: (@MainActor (Int, Int) -> Int)? = nil
  ) -> TextInputState {
    let id = widgetID
    interaction.registerFocusTargets(focusTargets, id: id)
    return interaction.registerTextInput(
      id: id, rect: rect, text: text, onChange: { _ in },
      pointerOffset: pointerOffset, verticalOffset: verticalOffset,
      navigationIgnored: navigationIgnored, readOnly: true)
  }

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

extension Host {
  package var context: BlockContext { runtime.context }
}

extension BlockContext {
}
