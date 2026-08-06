extension Block {
  public func frame(
    width: Float? = nil,
    height: Float? = nil,
    alignment: Alignment = .center
  ) -> FrameBlock {
    FrameBlock(
      content: self, width: width, height: height,
      maxWidth: nil, maxHeight: nil, alignment: alignment
    )
  }

  public func frame(
    maxWidth: Float? = nil,
    maxHeight: Float? = nil,
    alignment: Alignment = .center
  ) -> FrameBlock {
    FrameBlock(
      content: self, width: nil, height: nil,
      maxWidth: maxWidth, maxHeight: maxHeight, alignment: alignment
    )
  }

  public func padding(_ insets: EdgeInsets) -> PaddingBlock {
    PaddingBlock(content: self, insets: insets)
  }

  public func padding(_ amount: Float) -> PaddingBlock {
    padding(EdgeInsets(amount))
  }

  public func background(_ background: any Block) -> BackgroundBlock {
    BackgroundBlock(content: self, background: background)
  }

  public func border(_ color: Color, width: Float = 1) -> BorderBlock {
    BorderBlock(content: self, color: color, width: width)
  }

  public func clipped() -> ClipBlock {
    ClipBlock(content: self)
  }
}

public struct FrameBlock: PrimitiveBlock {
  public var content: any Block
  public var width: Float?
  public var height: Float?
  public var maxWidth: Float?
  public var maxHeight: Float?
  public var alignment: Alignment

  @MainActor public var expandsHorizontally: Bool { maxWidth != nil }
  @MainActor public var expandsVertically: Bool { maxHeight != nil }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let childSize = BlockEngine.measure(
      content,
      proposal: Size(width: width ?? proposal.width, height: height ?? proposal.height), context: context)
    return Size(
      width: width ?? maxWidth.map { min(proposal.width, $0) } ?? childSize.width,
      height: height ?? maxHeight.map { min(proposal.height, $0) } ?? childSize.height
    )
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let childSize = BlockEngine.measure(
      content,
      proposal: Size(width: width ?? rect.size.width, height: height ?? rect.size.height), context: context)
    BlockEngine.draw(content, into: &drawList, in: rect.placing(childSize, alignment: alignment), context: context)
  }
}

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

public struct BackgroundBlock: PrimitiveBlock {
  public var content: any Block
  public var background: any Block

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(background, into: &drawList, in: rect, context: context)
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}

public struct ClipBlock: PrimitiveBlock {
  public var content: any Block

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    drawList.pushClip(rect)
    context.withInteractionClip(rect) {
      BlockEngine.draw(content, into: &drawList, in: rect, context: context)
    }
    drawList.popClip()
  }
}

public struct BorderBlock: PrimitiveBlock {
  public var content: any Block
  public var color: Color
  public var width: Float

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
    drawList.strokeRect(rect, width: width, color: color)
  }
}
