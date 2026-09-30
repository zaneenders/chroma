struct ContextModifier: PrimitiveBlock, CollectionDistributingBlock {
  enum Operation {
    case hover(HoverStyle)
    case navigationIgnored
  }

  var content: any Block
  var operation: Operation

  var preservesContentIdentity: Bool { true }

  var focusRule: FocusRule { .container }

  @MainActor var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    draw(into: &drawList, in: rect, context: context) { list, rect, context in
      BlockEngine.draw(content, into: &list, in: rect, context: context)
    }
  }

  @MainActor func draw(
    into drawList: inout DrawList, in rect: Rect, context: BlockContext,
    drawContent: (inout DrawList, Rect, BlockContext) -> Void
  ) {
    var context = context
    switch operation {
    case .hover(let style): context.hoverStyle = style
    case .navigationIgnored: context.navigationIgnored = true
    }
    drawContent(&drawList, rect, context)
  }
}
