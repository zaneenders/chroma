public struct PaddingBlock: PrimitiveBlock {
  public var content: any Block
  public var insets: EdgeInsets

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let childSize = BlockEngine.measure(
      content,
      proposal: Size(
        width: max(0, proposal.width - insets.leading - insets.trailing),
        height: max(0, proposal.height - insets.top - insets.bottom)
      ), context: context)
    return Size(
      width: childSize.width + insets.leading + insets.trailing,
      height: childSize.height + insets.top + insets.bottom
    )
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(
      content,
      into: &drawList,
      in: Rect(
        x: rect.minX + insets.leading,
        y: rect.minY + insets.top,
        width: rect.size.width - insets.leading - insets.trailing,
        height: rect.size.height - insets.top - insets.bottom
      ), context: context)
  }
}
