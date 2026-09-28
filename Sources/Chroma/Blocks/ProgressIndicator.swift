import Foundation

public struct ProgressIndicator: PrimitiveBlock {
  public var color: Color
  public var diameter: Float
  public var isActive: Bool

  public init(color: Color = .white, diameter: Float = 12, isActive: Bool = true) {
    precondition(diameter.isFinite && diameter > 0)
    self.color = color
    self.diameter = diameter
    self.isActive = isActive
  }

  public var focusRule: FocusRule { .decorative }

  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    Size(width: diameter, height: diameter)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    let timestamp = context.animationFrame(active: isActive, updatesPerSecond: 11).timestamp
    let head = isActive ? Int(timestamp * 11) % 8 : 0
    let dot = diameter / 5
    let radius = (diameter - dot) / 2
    for index in 0..<8 {
      let angle = Float(index) * .pi / 4 - .pi / 2
      let age = (head - index + 8) % 8
      drawList.fillRoundedRect(
        Rect(
          x: rect.minX + diameter / 2 + cos(angle) * radius - dot / 2,
          y: rect.minY + rect.size.height / 2 + sin(angle) * radius - dot / 2,
          width: dot, height: dot),
        radius: dot / 2,
        color: Color(r: color.r, g: color.g, b: color.b, a: color.a * max(0.18, 1 - Float(age) * 0.12)))
    }
  }
}
