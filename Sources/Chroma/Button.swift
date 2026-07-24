/// A text button with a simple built-in style: hover and press feedback, and
/// an action fired on click.
///
/// For full control over appearance, build on ``Interactive`` directly.
///
/// ```swift
/// Button("Increment") { state.count += 1 }
/// ```
public struct Button: Block {
  public var label: String
  public var id: WidgetID
  public var action: () -> Void
  public var fontScale: Float
  public var textColor: Color
  public var idleColor: Color
  public var hoveredColor: Color
  public var pressedColor: Color
  public var borderColor: Color
  public var padding: EdgeInsets

  /// The button's ID defaults to its label; pass `id` to disambiguate two
  /// buttons that share a visible label.
  public init(
    _ label: String,
    id: WidgetID? = nil,
    fontScale: Float = 1,
    textColor: Color = .white,
    idleColor: Color = Color(r: 0.18, g: 0.20, b: 0.30, a: 1),
    hoveredColor: Color = Color(r: 0.24, g: 0.28, b: 0.42, a: 1),
    pressedColor: Color = Color(r: 0.30, g: 0.60, b: 1.00, a: 1),
    borderColor: Color = Color(r: 0.22, g: 0.22, b: 0.32, a: 1),
    padding: EdgeInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16),
    action: @escaping () -> Void
  ) {
    self.label = label
    self.id = id ?? WidgetID(label)
    self.action = action
    self.fontScale = fontScale
    self.textColor = textColor
    self.idleColor = idleColor
    self.hoveredColor = hoveredColor
    self.pressedColor = pressedColor
    self.borderColor = borderColor
    self.padding = padding
  }

  public var body: some Block {
    Interactive(id: id, action: action) { phase in
      Text(label)
        .fontScale(fontScale)
        .foregroundColor(textColor)
        .padding(padding)
        .background(color(for: phase))
        .border(borderColor, width: 1)
    }
  }

  private func color(for phase: InteractionPhase) -> Color {
    switch phase {
    case .idle: idleColor
    case .hovered: hoveredColor
    case .pressed: pressedColor
    }
  }
}
