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
}
