public enum DrawCommand: Equatable, Sendable {
  case fillRect(rect: Rect, color: Color)
  case strokeRect(rect: Rect, width: Float, color: Color)
  case fillRoundedRect(rect: Rect, radii: CornerRadii, color: Color)
  case strokeRoundedRect(rect: Rect, radii: CornerRadii, width: Float, color: Color)
  case text(position: Point, text: String, color: Color, scale: Float)
  case pushClip(Rect)
  case popClip
}
