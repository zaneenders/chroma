extension Block {
  public func sizing(x: Sizing = .fit, y: Sizing = .fit) -> some Block {
    LayoutModifier(content: self, operation: .sizing(x: x, y: y))
  }

  public func padding(_ insets: EdgeInsets) -> some Block {
    LayoutModifier(content: self, operation: .padding(insets))
  }

  public func padding(_ amount: Float) -> some Block {
    padding(EdgeInsets(amount))
  }

  public func background(_ background: any Block) -> some Block {
    PaintModifier(content: self, operation: .background(background))
  }

  public func border(_ color: Color, width: Float = 1) -> some Block {
    PaintModifier(content: self, operation: .border(color, .zero, width))
  }

  public func roundedBackground(_ color: Color, radius: Float) -> some Block {
    PaintModifier(content: self, operation: .roundedBackground(color, CornerRadii(radius)))
  }

  public func roundedBackground(_ color: Color, radii: CornerRadii) -> some Block {
    PaintModifier(content: self, operation: .roundedBackground(color, radii))
  }

  public func roundedBorder(
    _ color: Color, radius: Float, width: Float = 1
  ) -> some Block {
    PaintModifier(content: self, operation: .border(color, CornerRadii(radius), width))
  }

  public func roundedBorder(
    _ color: Color, radii: CornerRadii, width: Float = 1
  ) -> some Block {
    PaintModifier(content: self, operation: .border(color, radii, width))
  }

  public func clipped() -> some Block {
    PaintModifier(content: self, operation: .clip)
  }
}
