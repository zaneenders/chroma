public struct DrawList: Sendable {
  public private(set) var commands: [DrawCommand] = []

  public init() {}

  public mutating func fillRect(_ rect: Rect, color: Color) {
    commands.append(.fillRect(rect: rect, color: color))
  }

  public mutating func strokeRect(_ rect: Rect, width: Float, color: Color) {
    commands.append(.strokeRect(rect: rect, width: width, color: color))
  }

  public mutating func text(_ text: String, at position: Point, color: Color, scale: Float = 1) {
    commands.append(.text(position: position, text: text, color: color, scale: scale))
  }

  public mutating func pushClip(_ rect: Rect) {
    commands.append(.pushClip(rect))
  }

  public mutating func popClip() {
    commands.append(.popClip)
  }
}
