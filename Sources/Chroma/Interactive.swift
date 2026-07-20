/// A region of UI with press interaction: a leaf of the focus tree.
///
/// Every frame the region registers itself with the ambient ``Interaction``
/// context, styles its content for the resulting ``InteractionPhase``, and
/// fires `action` when it is activated — by a click, or by an `activate`
/// command while the navigation cursor is on it (press inside, drag outside,
/// release does not click).
///
/// This is the building block for buttons, checkboxes, and anything else
/// clickable; the content closure is re-invoked each frame with the current
/// phase:
///
/// ```swift
/// Interactive(id: WidgetID("save"), action: { state.save() }) { phase in
///   Text("Save")
///     .padding(8)
///     .background(phase == .pressed ? accent : idle)
/// }
/// ```
public struct Interactive<Content: Block>: PrimitiveBlock {
  /// The widget's stable identity for hot/active tracking.
  public var id: WidgetID
  /// Fired when a press completes inside the region.
  public var action: () -> Void
  /// Builds the region's content for the current interaction phase.
  public var content: (InteractionPhase) -> Content

  public init(
    id: WidgetID,
    action: @escaping () -> Void,
    content: @escaping (InteractionPhase) -> Content
  ) {
    self.id = id
    self.action = action
    self.content = content
  }

  public init(
    id: String,
    action: @escaping () -> Void,
    content: @escaping (InteractionPhase) -> Content
  ) {
    self.init(id: WidgetID(id), action: action, content: content)
  }

  // Measurement and expansion use the idle phase: styling must not change
  // size between phases, or hovering would shift layout.

  @MainActor public var expandsHorizontally: Bool {
    BlockEngine.expandsHorizontally(content(.idle))
  }

  @MainActor public var expandsVertically: Bool {
    BlockEngine.expandsVertically(content(.idle))
  }

  @MainActor public func sizeThatFits(_ proposal: Size) -> Size {
    BlockEngine.measure(content(.idle), proposal: proposal)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    let state = Interaction.current.interactiveBehavior(id: id, rect: rect)
    if state.clicked { action() }
    BlockEngine.draw(content(state.phase), into: &drawList, in: rect)
  }
}
