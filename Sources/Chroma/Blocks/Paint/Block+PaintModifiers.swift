extension Block {
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
