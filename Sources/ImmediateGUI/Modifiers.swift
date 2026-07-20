extension Block {
  /// A fixed-size frame. Omitted dimensions keep the content's size.
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

  /// A greedy frame: `.infinity` dimensions take all proposed space, making
  /// the block expand in stacks. Finite values cap the proposal instead.
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

  /// Insets the content on all edges by the given amounts.
  public func padding(_ insets: EdgeInsets) -> PaddingBlock {
    PaddingBlock(content: self, insets: insets)
  }

  /// Insets the content on all edges by `amount`.
  public func padding(_ amount: Float) -> PaddingBlock {
    padding(EdgeInsets(amount))
  }

  /// Draws `background` behind the content, sized to the content.
  public func background(_ background: any Block) -> BackgroundBlock {
    BackgroundBlock(content: self, background: background)
  }

  /// Strokes a border inside the content's rect.
  public func border(_ color: Color, width: Float = 1) -> BorderBlock {
    BorderBlock(content: self, color: color, width: width)
  }
}

/// A frame around a block: fixed dimensions, greedy `.infinity` dimensions,
/// and alignment of the content within the frame.
public struct FrameBlock: PrimitiveBlock {
  public var content: any Block
  public var width: Float?
  public var height: Float?
  public var maxWidth: Float?
  public var maxHeight: Float?
  public var alignment: Alignment

  public var expandsHorizontally: Bool { maxWidth != nil }
  public var expandsVertically: Bool { maxHeight != nil }

  public func sizeThatFits(_ proposal: Size) -> Size {
    let childSize = BlockEngine.measure(
      content,
      proposal: Size(width: width ?? proposal.width, height: height ?? proposal.height)
    )
    return Size(
      width: width ?? maxWidth.map { min(proposal.width, $0) } ?? childSize.width,
      height: height ?? maxHeight.map { min(proposal.height, $0) } ?? childSize.height
    )
  }

  public func draw(into drawList: inout DrawList, in rect: Rect) {
    let childSize = BlockEngine.measure(
      content,
      proposal: Size(width: width ?? rect.size.width, height: height ?? rect.size.height)
    )
    BlockEngine.draw(content, into: &drawList, in: rect.placing(childSize, alignment: alignment))
  }
}

/// Insets around a block.
public struct PaddingBlock: PrimitiveBlock {
  public var content: any Block
  public var insets: EdgeInsets

  public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  public func sizeThatFits(_ proposal: Size) -> Size {
    let childSize = BlockEngine.measure(
      content,
      proposal: Size(
        width: max(0, proposal.width - insets.leading - insets.trailing),
        height: max(0, proposal.height - insets.top - insets.bottom)
      )
    )
    return Size(
      width: childSize.width + insets.leading + insets.trailing,
      height: childSize.height + insets.top + insets.bottom
    )
  }

  public func draw(into drawList: inout DrawList, in rect: Rect) {
    BlockEngine.draw(
      content,
      into: &drawList,
      in: Rect(
        x: rect.minX + insets.leading,
        y: rect.minY + insets.top,
        width: rect.size.width - insets.leading - insets.trailing,
        height: rect.size.height - insets.top - insets.bottom
      )
    )
  }
}

/// A block drawn on top of a background sized to it.
public struct BackgroundBlock: PrimitiveBlock {
  public var content: any Block
  public var background: any Block

  public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  public func sizeThatFits(_ proposal: Size) -> Size {
    BlockEngine.measure(content, proposal: proposal)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect) {
    BlockEngine.draw(background, into: &drawList, in: rect)
    BlockEngine.draw(content, into: &drawList, in: rect)
  }
}

/// A block with a border stroked inside its rect.
public struct BorderBlock: PrimitiveBlock {
  public var content: any Block
  public var color: Color
  public var width: Float

  public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  public func sizeThatFits(_ proposal: Size) -> Size {
    BlockEngine.measure(content, proposal: proposal)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect) {
    BlockEngine.draw(content, into: &drawList, in: rect)
    drawList.strokeRect(rect, width: width, color: color)
  }
}
