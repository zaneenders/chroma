extension Button {
  @available(*, unavailable, message: "Buttons must remain navigable.")
  public func navigationIgnored() -> some Block {
    ContextModifier(content: self, operation: .navigationIgnored)
  }
}

extension Block {
  public func navigationIgnored() -> some Block {
    ContextModifier(content: self, operation: .navigationIgnored)
  }
}
