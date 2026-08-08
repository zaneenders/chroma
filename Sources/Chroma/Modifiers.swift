extension Block {
  public func sizing(
    x: Sizing = .fit,
    y: Sizing = .fit
  ) -> SizingBlock {
    SizingBlock(content: self, x: x, y: y)
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

  public func roundedBackground(_ color: Color, radius: Float) -> RoundedBackgroundBlock {
    RoundedBackgroundBlock(content: self, color: color, radii: CornerRadii(radius))
  }

  public func roundedBackground(_ color: Color, radii: CornerRadii) -> RoundedBackgroundBlock {
    RoundedBackgroundBlock(content: self, color: color, radii: radii)
  }

  public func roundedBorder(
    _ color: Color, radius: Float, width: Float = 1
  ) -> RoundedBorderBlock {
    RoundedBorderBlock(content: self, color: color, radii: CornerRadii(radius), width: width)
  }

  public func roundedBorder(
    _ color: Color, radii: CornerRadii, width: Float = 1
  ) -> RoundedBorderBlock {
    RoundedBorderBlock(content: self, color: color, radii: radii, width: width)
  }

  public func clipped() -> ClipBlock {
    ClipBlock(content: self)
  }
}

public struct SizingBlock: PrimitiveBlock {
  public var content: any Block
  public var x: Sizing
  public var y: Sizing

  @MainActor public var expandsHorizontally: Bool { x == .grow }
  @MainActor public var expandsVertically: Bool { y == .grow }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let childSize = BlockEngine.measure(
      content,
      proposal: Size(
        width: proposedSize(for: x, available: proposal.width),
        height: proposedSize(for: y, available: proposal.height)
      ),
      context: context
    )
    return Size(
      width: resolvedSize(for: x, available: proposal.width, fitted: childSize.width),
      height: resolvedSize(for: y, available: proposal.height, fitted: childSize.height)
    )
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }

  private func proposedSize(for sizing: Sizing, available: Float) -> Float {
    switch sizing {
    case .fit, .grow: available
    case .fixed(let size): size
    }
  }

  private func resolvedSize(for sizing: Sizing, available: Float, fitted: Float) -> Float {
    switch sizing {
    case .fit: fitted
    case .fixed(let size): size
    case .grow: available
    }
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

public struct RoundedBackgroundBlock: PrimitiveBlock {
  public var content: any Block
  public var color: Color
  public var radii: CornerRadii

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    drawList.fillRoundedRect(rect, radii: radii, color: color)
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}

public struct RoundedBorderBlock: PrimitiveBlock {
  public var content: any Block
  public var color: Color
  public var radii: CornerRadii
  public var width: Float

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
    drawList.strokeRoundedRect(rect, radii: radii, width: width, color: color)
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
