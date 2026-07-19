/// An RGBA color with float components in the range 0...1.
public struct Color: Equatable, Sendable {
  public var r: Float
  public var g: Float
  public var b: Float
  public var a: Float

  public init(r: Float, g: Float, b: Float, a: Float) {
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  }

  public static let clear = Color(r: 0, g: 0, b: 0, a: 0)
  public static let black = Color(r: 0, g: 0, b: 0, a: 1)
  public static let white = Color(r: 1, g: 1, b: 1, a: 1)
  public static let yellow = Color(r: 1, g: 0.78, b: 0.25, a: 1)
}
