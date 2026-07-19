/// A point in pixel space with a top-left origin.
struct Point: Equatable {
  var x: Float
  var y: Float

  static let zero = Point(x: 0, y: 0)
}
