struct PaintModifier: Block {
  enum Operation {
    case background(any Block)
    case roundedBackground(Color, CornerRadii)
    case border(Color, CornerRadii, Float)
    case clip
  }

  var content: any Block
  var operation: Operation

}
