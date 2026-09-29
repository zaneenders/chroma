public enum HoverStyle: Equatable, Sendable {
  case standard
  case none
  case tint(Color)

  public static func standardTint(in theme: ChromaTheme, pressed: Bool = false) -> Color {
    let base = pressed ? theme.focus.pressedHighlight : theme.focus.highlight
    return Color(r: base.r, g: base.g, b: base.b, a: base.a * 0.5)
  }
}

public struct HoverStyleBlock: PrimitiveBlock, IdentityTransparentBlock {
  public var content: any Block
  public var style: HoverStyle

  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    var context = context
    context.hoverStyle = style
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}

extension Block {
  public func hover(_ style: HoverStyle) -> HoverStyleBlock {
    HoverStyleBlock(content: self, style: style)
  }
}
