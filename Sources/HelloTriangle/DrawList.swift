/// The ordered drawing commands for one frame.
///
/// Application code appends commands; backends consume them without knowing
/// what produced them.
struct DrawList {
  private(set) var commands: [DrawCommand] = []

  mutating func text(_ text: String, at position: Point, color: Color, scale: Float = 1) {
    commands.append(.text(position: position, text: text, color: color, scale: scale))
  }
}
