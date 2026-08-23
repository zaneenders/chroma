public struct ButtonStyle: Equatable, Sendable {
  public var idleBackground: Color
  public var hoveredBackground: Color
  public var pressedBackground: Color
  public var foreground: Color
  public var border: Color
  public var cornerRadius: Float
  public var borderWidth: Float

  public init(
    idleBackground: Color,
    hoveredBackground: Color,
    pressedBackground: Color,
    foreground: Color,
    border: Color,
    cornerRadius: Float = 6,
    borderWidth: Float = 1
  ) {
    self.idleBackground = idleBackground
    self.hoveredBackground = hoveredBackground
    self.pressedBackground = pressedBackground
    self.foreground = foreground
    self.border = border
    self.cornerRadius = cornerRadius
    self.borderWidth = borderWidth
  }
}

public struct TextFieldStyle: Equatable, Sendable {
  public var idleBackground: Color
  public var hoveredBackground: Color
  public var editingBackground: Color
  public var foreground: Color
  public var placeholder: Color
  public var caret: Color
  public var border: Color
  public var editingBorder: Color
  public var cornerRadius: Float
  public var borderWidth: Float

  public init(
    idleBackground: Color,
    hoveredBackground: Color,
    editingBackground: Color,
    foreground: Color,
    placeholder: Color,
    caret: Color,
    border: Color,
    editingBorder: Color,
    cornerRadius: Float = 6,
    borderWidth: Float = 1
  ) {
    self.idleBackground = idleBackground
    self.hoveredBackground = hoveredBackground
    self.editingBackground = editingBackground
    self.foreground = foreground
    self.placeholder = placeholder
    self.caret = caret
    self.border = border
    self.editingBorder = editingBorder
    self.cornerRadius = cornerRadius
    self.borderWidth = borderWidth
  }
}

public struct ScrollViewStyle: Equatable, Sendable {
  public var indicator: Color
  public var indicatorThickness: Float
  public var minimumThumbLength: Float

  public init(
    indicator: Color,
    indicatorThickness: Float = 3,
    minimumThumbLength: Float = 12
  ) {
    self.indicator = indicator
    self.indicatorThickness = indicatorThickness
    self.minimumThumbLength = minimumThumbLength
  }
}

public struct FocusStyle: Equatable, Sendable {
  public var ring: Color
  public var selectionBackground: Color
  public var selectionForeground: Color

  public init(ring: Color, selectionBackground: Color, selectionForeground: Color) {
    self.ring = ring
    self.selectionBackground = selectionBackground
    self.selectionForeground = selectionForeground
  }
}

public struct ChromaTheme: Equatable, Sendable {
  public var background: Color
  public var surface: Color
  public var elevatedSurface: Color
  public var foreground: Color
  public var secondaryForeground: Color
  public var border: Color
  public var accent: Color
  public var positive: Color
  public var negative: Color
  public var warning: Color
  public var button: ButtonStyle
  public var textField: TextFieldStyle
  public var scrollView: ScrollViewStyle
  public var focus: FocusStyle

  public init(
    background: Color,
    surface: Color,
    elevatedSurface: Color,
    foreground: Color,
    secondaryForeground: Color,
    border: Color,
    accent: Color,
    positive: Color,
    negative: Color,
    warning: Color,
    button: ButtonStyle,
    textField: TextFieldStyle,
    scrollView: ScrollViewStyle,
    focus: FocusStyle
  ) {
    self.background = background
    self.surface = surface
    self.elevatedSurface = elevatedSurface
    self.foreground = foreground
    self.secondaryForeground = secondaryForeground
    self.border = border
    self.accent = accent
    self.positive = positive
    self.negative = negative
    self.warning = warning
    self.button = button
    self.textField = textField
    self.scrollView = scrollView
    self.focus = focus
  }

  public func accentColor(_ color: Color) -> ChromaTheme {
    var copy = self
    copy.accent = color
    copy.button.pressedBackground = color
    copy.textField.editingBorder = color
    copy.focus.ring = color
    return copy
  }

  public static let dark = ChromaTheme(
    background: Color(r: 0.045, g: 0.055, b: 0.075, a: 1),
    surface: Color(r: 0.065, g: 0.075, b: 0.10, a: 1),
    elevatedSurface: Color(r: 0.075, g: 0.09, b: 0.13, a: 1),
    foreground: .white,
    secondaryForeground: Color(r: 0.52, g: 0.56, b: 0.66, a: 1),
    border: Color(r: 0.16, g: 0.19, b: 0.25, a: 1),
    accent: Color(r: 0.20, g: 0.62, b: 0.98, a: 1),
    positive: Color(r: 0.3, g: 0.8, b: 0.4, a: 1),
    negative: Color(r: 0.9, g: 0.3, b: 0.3, a: 1),
    warning: Color(r: 1, g: 0.85, b: 0.25, a: 1),
    button: ButtonStyle(
      idleBackground: Color(r: 0.09, g: 0.11, b: 0.15, a: 1),
      hoveredBackground: Color(r: 0.12, g: 0.16, b: 0.23, a: 1),
      pressedBackground: Color(r: 0.20, g: 0.62, b: 0.98, a: 1),
      foreground: .white,
      border: Color(r: 0.16, g: 0.19, b: 0.25, a: 1)),
    textField: TextFieldStyle(
      idleBackground: Color(r: 0.09, g: 0.11, b: 0.15, a: 1),
      hoveredBackground: Color(r: 0.12, g: 0.16, b: 0.23, a: 1),
      editingBackground: Color(r: 0.055, g: 0.07, b: 0.11, a: 1),
      foreground: .white,
      placeholder: Color(r: 0.45, g: 0.48, b: 0.57, a: 1),
      caret: .white,
      border: Color(r: 0.16, g: 0.19, b: 0.25, a: 1),
      editingBorder: Color(r: 0.20, g: 0.62, b: 0.98, a: 1)),
    scrollView: ScrollViewStyle(indicator: Color(r: 1, g: 1, b: 1, a: 0.45)),
    focus: FocusStyle(
      ring: Color(r: 0.20, g: 0.62, b: 0.98, a: 1),
      selectionBackground: Color(r: 0.3, g: 0.6, b: 1, a: 0.5),
      selectionForeground: .white)
  )

  public static let light = ChromaTheme(
    background: Color(r: 0.94, g: 0.95, b: 0.97, a: 1),
    surface: .white,
    elevatedSurface: Color(r: 0.88, g: 0.90, b: 0.94, a: 1),
    foreground: Color(r: 0.08, g: 0.10, b: 0.14, a: 1),
    secondaryForeground: Color(r: 0.35, g: 0.39, b: 0.46, a: 1),
    border: Color(r: 0.68, g: 0.71, b: 0.77, a: 1),
    accent: Color(r: 0.05, g: 0.38, b: 0.82, a: 1),
    positive: Color(r: 0.05, g: 0.52, b: 0.19, a: 1),
    negative: Color(r: 0.75, g: 0.10, b: 0.12, a: 1),
    warning: Color(r: 0.72, g: 0.45, b: 0.02, a: 1),
    button: ButtonStyle(
      idleBackground: Color(r: 0.88, g: 0.90, b: 0.94, a: 1),
      hoveredBackground: Color(r: 0.80, g: 0.84, b: 0.91, a: 1),
      pressedBackground: Color(r: 0.05, g: 0.38, b: 0.82, a: 1),
      foreground: Color(r: 0.08, g: 0.10, b: 0.14, a: 1),
      border: Color(r: 0.68, g: 0.71, b: 0.77, a: 1)),
    textField: TextFieldStyle(
      idleBackground: .white,
      hoveredBackground: Color(r: 0.96, g: 0.97, b: 0.99, a: 1),
      editingBackground: .white,
      foreground: Color(r: 0.08, g: 0.10, b: 0.14, a: 1),
      placeholder: Color(r: 0.45, g: 0.48, b: 0.54, a: 1),
      caret: .black,
      border: Color(r: 0.68, g: 0.71, b: 0.77, a: 1),
      editingBorder: Color(r: 0.05, g: 0.38, b: 0.82, a: 1)),
    scrollView: ScrollViewStyle(indicator: Color(r: 0, g: 0, b: 0, a: 0.45)),
    focus: FocusStyle(
      ring: Color(r: 0.05, g: 0.38, b: 0.82, a: 1),
      selectionBackground: Color(r: 0.20, g: 0.52, b: 0.95, a: 0.45),
      selectionForeground: .black)
  )

  public static let highContrast = ChromaTheme(
    background: .black,
    surface: .black,
    elevatedSurface: Color(r: 0.08, g: 0.08, b: 0.08, a: 1),
    foreground: .white,
    secondaryForeground: .white,
    border: .white,
    accent: .yellow,
    positive: Color(r: 0, g: 1, b: 0, a: 1),
    negative: Color(r: 1, g: 0.2, b: 0.2, a: 1),
    warning: .yellow,
    button: ButtonStyle(
      idleBackground: .black, hoveredBackground: Color(r: 0.2, g: 0.2, b: 0.2, a: 1),
      pressedBackground: .yellow, foreground: .white, border: .white),
    textField: TextFieldStyle(
      idleBackground: .black, hoveredBackground: Color(r: 0.12, g: 0.12, b: 0.12, a: 1),
      editingBackground: .black, foreground: .white, placeholder: .white, caret: .yellow,
      border: .white, editingBorder: .yellow),
    scrollView: ScrollViewStyle(indicator: .white, indicatorThickness: 4),
    focus: FocusStyle(ring: .yellow, selectionBackground: .yellow, selectionForeground: .black)
  )
}

public struct ThemeReader<Content: Block>: PrimitiveBlock {
  public var content: (ChromaTheme) -> Content

  public init(@BlockBuilder content: @escaping (ChromaTheme) -> Content) {
    self.content = content
  }

  @MainActor public var expandsHorizontally: Bool { false }
  @MainActor public var expandsVertically: Bool { false }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content(context.theme), proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(content(context.theme), into: &drawList, in: rect, context: context)
  }
}

public struct ThemeBlock: PrimitiveBlock {
  public var content: any Block
  public var theme: ChromaTheme

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context.withTheme(theme))
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(content, into: &drawList, in: rect, context: context.withTheme(theme))
  }
}

extension Block {
  public func chromaTheme(_ theme: ChromaTheme) -> ThemeBlock {
    ThemeBlock(content: self, theme: theme)
  }
}
