/// An RGBA color with float components in the range 0...1.
struct Color: Equatable {
  var r: Float
  var g: Float
  var b: Float
  var a: Float

  static let clear = Color(r: 0, g: 0, b: 0, a: 0)
  static let black = Color(r: 0, g: 0, b: 0, a: 1)
  static let white = Color(r: 1, g: 1, b: 1, a: 1)
  static let yellow = Color(r: 1, g: 0.78, b: 0.25, a: 1)
}
