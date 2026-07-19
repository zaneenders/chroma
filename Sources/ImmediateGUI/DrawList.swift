/// The ordered drawing commands for one frame.
///
/// Application code appends commands; backends consume them without knowing
/// what produced them.
public struct DrawList: Sendable {
  public private(set) var commands: [DrawCommand] = []

  public init() {}

  public mutating func text(_ text: String, at position: Point, color: Color, scale: Float = 1) {
    commands.append(.text(position: position, text: text, color: color, scale: scale))
  }
}
