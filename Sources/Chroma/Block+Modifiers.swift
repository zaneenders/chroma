extension Block {
  public func sizing(x: Sizing = .fit, y: Sizing = .fit) -> SizingBlock {
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
