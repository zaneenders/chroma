/// A point in pixel space with a top-left origin.
struct Point: Equatable {
  var x: Float
  var y: Float

  static let zero = Point(x: 0, y: 0)
}

/// A size in pixel space.
struct Size: Equatable {
  var width: Float
  var height: Float

  static let zero = Size(width: 0, height: 0)
}

/// An axis-aligned rectangle in pixel space with a top-left origin.
struct Rect: Equatable {
  var origin: Point
  var size: Size

  var minX: Float { origin.x }
  var minY: Float { origin.y }
  var maxX: Float { origin.x + size.width }
  var maxY: Float { origin.y + size.height }

  func contains(_ point: Point) -> Bool {
    point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
  }

  func intersection(_ other: Rect) -> Rect? {
    let x0 = max(minX, other.minX)
    let y0 = max(minY, other.minY)
    let x1 = min(maxX, other.maxX)
    let y1 = min(maxY, other.maxY)
    guard x1 > x0, y1 > y0 else { return nil }
    return Rect(origin: Point(x: x0, y: y0), size: Size(width: x1 - x0, height: y1 - y0))
  }
}
