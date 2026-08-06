public struct CornerRadii: Equatable, Sendable {
  public var topLeft: Float
  public var topRight: Float
  public var bottomRight: Float
  public var bottomLeft: Float

  public init(
    topLeft: Float,
    topRight: Float,
    bottomRight: Float,
    bottomLeft: Float
  ) {
    self.topLeft = topLeft
    self.topRight = topRight
    self.bottomRight = bottomRight
    self.bottomLeft = bottomLeft
  }

  public init(_ radius: Float) {
    self.init(
      topLeft: radius,
      topRight: radius,
      bottomRight: radius,
      bottomLeft: radius)
  }

  /// Returns non-negative radii scaled so neighboring corners never overlap.
  public func normalized(for size: Size) -> CornerRadii {
    let tl = max(0, topLeft)
    let tr = max(0, topRight)
    let br = max(0, bottomRight)
    let bl = max(0, bottomLeft)
    let width = max(0, size.width)
    let height = max(0, size.height)

    var scale: Float = 1
    func constrain(_ available: Float, _ requested: Float) {
      if requested > 0 { scale = min(scale, available / requested) }
    }
    constrain(width, tl + tr)
    constrain(width, bl + br)
    constrain(height, tl + bl)
    constrain(height, tr + br)
    scale = max(0, min(1, scale))

    return CornerRadii(
      topLeft: tl * scale,
      topRight: tr * scale,
      bottomRight: br * scale,
      bottomLeft: bl * scale)
  }

  public static let zero = CornerRadii(0)
}
