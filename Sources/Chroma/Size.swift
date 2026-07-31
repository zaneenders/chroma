public struct Size: Equatable, Sendable {
  public var width: Float
  public var height: Float

  public init(width: Float, height: Float) {
    self.width = width
    self.height = height
  }

  public static let zero = Size(width: 0, height: 0)
}
