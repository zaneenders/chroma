public struct EdgeInsets: Equatable, Sendable {
  public var top: Float
  public var leading: Float
  public var bottom: Float
  public var trailing: Float

  public init(top: Float = 0, leading: Float = 0, bottom: Float = 0, trailing: Float = 0) {
    self.top = top
    self.leading = leading
    self.bottom = bottom
    self.trailing = trailing
  }

  public init(_ amount: Float) {
    self.init(top: amount, leading: amount, bottom: amount, trailing: amount)
  }
}
