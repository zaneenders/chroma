public struct FontMetrics: Equatable, Sendable {
  public var glyphWidth: Float = 20
  public var glyphHeight: Float = 28
  public var cellAdvance: Float = 12
  public var lineAdvance: Float = 32

  public init() {}

  public func measure(_ text: String, scale: Float = 1) -> Size {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    return Size(
      width: Float(lines.map(\.count).max() ?? 0) * cellAdvance * scale,
      height: (glyphHeight + Float(max(0, lines.count - 1)) * lineAdvance) * scale)
  }
}
