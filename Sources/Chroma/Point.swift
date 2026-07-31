public struct Point: Equatable, Sendable {
  public var x: Float
  public var y: Float

  public init(x: Float, y: Float) {
    self.x = x
    self.y = y
  }

  public static let zero = Point(x: 0, y: 0)
}
