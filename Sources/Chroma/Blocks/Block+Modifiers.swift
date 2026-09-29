extension Block {
  public func sizing(x: Sizing = .fit, y: Sizing = .fit) -> some Block {
    SizingBlock(content: self, x: x, y: y)
  }

  public func padding(_ insets: EdgeInsets) -> some Block {
    PaddingBlock(content: self, insets: insets)
  }

  public func padding(_ amount: Float) -> some Block {
    padding(EdgeInsets(amount))
  }

  public func background(_ background: any Block) -> some Block {
    BackgroundBlock(content: self, background: background)
  }

  public func border(_ color: Color, width: Float = 1) -> some Block {
    BorderBlock(content: self, color: color, width: width)
  }

  public func roundedBackground(_ color: Color, radius: Float) -> some Block {
    RoundedBackgroundBlock(content: self, color: color, radii: CornerRadii(radius))
  }

  public func roundedBackground(_ color: Color, radii: CornerRadii) -> some Block {
    RoundedBackgroundBlock(content: self, color: color, radii: radii)
  }

  public func roundedBorder(
    _ color: Color, radius: Float, width: Float = 1
  ) -> some Block {
    BorderBlock(content: self, color: color, radii: CornerRadii(radius), width: width)
  }

  public func roundedBorder(
    _ color: Color, radii: CornerRadii, width: Float = 1
  ) -> some Block {
    BorderBlock(content: self, color: color, radii: radii, width: width)
  }

  public func clipped() -> some Block {
    ClipBlock(content: self)
  }
}
