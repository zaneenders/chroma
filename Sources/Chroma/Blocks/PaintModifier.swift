struct PaintModifier: PrimitiveBlock, CollectionDistributingBlock {
  enum Operation {
    case background(any Block)
    case roundedBackground(Color, CornerRadii)
    case border(Color, CornerRadii, Float)
    case clip
  }

  var content: any Block
  var operation: Operation

  var focusRule: FocusRule { .container }

  @MainActor var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    switch operation {
    case .background:
      BlockEngine.measure(content, proposal: proposal, context: context.backgroundContentContext)
    case .roundedBackground, .border, .clip:
      BlockEngine.measure(content, proposal: proposal, context: context)
    }
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
    switch operation {
    case .background(let background):
      BlockEngine.draw(background, into: &drawList, in: rect, context: context.backgroundContext)
      drawContent(&drawList, rect, context.backgroundContentContext)
    case .roundedBackground(let color, let radii):
      drawList.fillRoundedRect(rect, radii: radii, color: color)
      drawContent(&drawList, rect, context)
    case .border(let color, let radii, let width):
      drawContent(&drawList, rect, context)
      if radii == .zero {
        drawList.strokeRect(rect, width: width, color: color)
      } else {
        drawList.strokeRoundedRect(rect, radii: radii, width: width, color: color)
      }
    case .clip:
      drawList.pushClip(rect)
      context.withInteractionClip(rect) {
        drawContent(&drawList, rect, context)
      }
      drawList.popClip()
    }
  }
}
