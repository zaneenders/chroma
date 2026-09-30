import Foundation

public struct MarqueeText: PrimitiveBlock {
  public var text: String
  public var color: Color
  public var fontScale: Float
  public var isActive: Bool

  public init(_ text: String, color: Color = .white, fontScale: Float = 1, isActive: Bool = true) {
    self.text = text
    self.color = color
    self.fontScale = fontScale
    self.isActive = isActive
  }

  public var focusRule: FocusRule { .standard }
  public var expandsHorizontally: Bool { true }

  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    Size(width: proposal.width, height: context.fontMetrics.measure(text, scale: fontScale * context.textScale).height)
  }

  public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    let scale = fontScale * context.textScale
    let width = context.fontMetrics.measure(text, scale: scale).width
    var offset: Float = 0
    if isActive, width > rect.size.width, rect.size.width > 0 {
      let now = context.animationTimestamp
      let distance = Double(width - rect.size.width)
      let travel = distance / 28
      let pause = 0.8
      let cycle = 2 * (pause + travel)
      let phase = now.truncatingRemainder(dividingBy: cycle)
      if phase < pause {
        context.requestAnimation(at: now + pause - phase)
      } else if phase < pause + travel {
        offset = Float((phase - pause) * 28)
        context.requestAnimation(updatesPerSecond: 30)
      } else if phase < 2 * pause + travel {
        offset = Float(distance)
        context.requestAnimation(at: now + 2 * pause + travel - phase)
      } else {
        offset = Float(distance - (phase - 2 * pause - travel) * 28)
        context.requestAnimation(updatesPerSecond: 30)
      }
    }
    drawList.pushClip(rect)
    drawList.text(text, at: Point(x: rect.minX - offset, y: rect.minY), color: color, scale: scale)
    drawList.popClip()
  }
}
