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
    drawList.pushClip(rect)
    drawList.text(text, at: rect.origin, color: color, scale: scale)
    drawList.popClip()
  }
}
