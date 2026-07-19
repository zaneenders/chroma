/// A size in pixel space.
struct Size: Equatable {
  var width: Float
  var height: Float

  static let zero = Size(width: 0, height: 0)
}
