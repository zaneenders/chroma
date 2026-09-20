/// The highlight drawn over content that is keyboard-focused or pointer-hovered.
public enum HoverStyle: Equatable, Sendable {
  /// Translucent `button.hoveredBackground` tint (accent while pressed).
  case standard
  /// The content is decorative: it registers no default focus leaf and draws no highlight.
  case none
  /// A custom translucent tint; the color's own alpha is respected.
  case tint(Color)

  /// The tint the standard style draws.
  public static func standardTint(in theme: ChromaTheme, pressed: Bool = false) -> Color {
    let base = pressed ? theme.button.pressedBackground : theme.button.hoveredBackground
    return Color(r: base.r, g: base.g, b: base.b, a: base.a * 0.5)
  }
}

/// Keys the highlight override carried by `hover(_:)` through the structural tree.
public struct HoverStyleBlock: PrimitiveBlock, IdentityTransparentBlock {
  public var content: any Block
  public var style: HoverStyle

  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    var context = context
    context.hoverStyle = style
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}

extension Block {
  /// Overrides the default interactivity of this content: every visible block is
  /// keyboard-focusable and pointer-hoverable with a standard highlight. `.none` marks
  /// decorative content — it registers no focus leaf; `.tint` keeps the leaf but draws a
  /// custom highlight. Leaves registered by `focusable` honor it; controls that draw
  /// their own state (Button, TextField, Interactive) ignore it.
  public func hover(_ style: HoverStyle) -> HoverStyleBlock {
    HoverStyleBlock(content: self, style: style)
  }
}
