/// An axis-aligned rectangle in pixel space with a top-left origin.
public struct Rect: Equatable, Sendable {
  public var origin: Point
  public var size: Size

  public init(origin: Point, size: Size) {
    self.origin = origin
    self.size = size
  }

  /// Creates a rect from individual coordinates.
  public init(x: Float, y: Float, width: Float, height: Float) {
    self.init(origin: Point(x: x, y: y), size: Size(width: width, height: height))
  }

  public var minX: Float { origin.x }
  public var minY: Float { origin.y }
  public var maxX: Float { origin.x + size.width }
  public var maxY: Float { origin.y + size.height }

  public func contains(_ point: Point) -> Bool {
    point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
  }

  public static let zero = Rect(origin: .zero, size: .zero)

  public func intersection(_ other: Rect) -> Rect? {
    let x0 = max(minX, other.minX)
    let y0 = max(minY, other.minY)
    let x1 = min(maxX, other.maxX)
    let y1 = min(maxY, other.maxY)
    guard x1 > x0, y1 > y0 else { return nil }
    return Rect(origin: Point(x: x0, y: y0), size: Size(width: x1 - x0, height: y1 - y0))
  }
}
