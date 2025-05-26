typealias ANSIString = String

extension ChromaShell.Color {
  public static func random() -> ChromaShell.Color {
    let colors = Self.allCases
    let r = Int.random(in: 0..<colors.count)
    for (i, color) in colors.enumerated() {
      if i == r {
        return color
      }
    }
    return .default
  }
}

/// A wrapper to help make printing color to the terminal easier.
public enum ChromaShell {

  public enum TerminalColor {
    case reset
    case basic(Basic)
    case bright(Basic)
    case int(Int)

    public enum Basic {
      case black
      case red
      case green
      case yellow
      case blue
      case magenta
      case cyan
      case white
    }
  }

  public enum Color: CaseIterable {
    case yellow
    case blue
    case pink
    case red
    case orange
    case purple
    case teal
    case white
    case green
    case black
    case `default`
  }

  // BUG background color doesn't seem to work
  public static func wrap(
    _ out: String,
    _ foreground: Color = .default,
    _ background: Color = .default
  ) -> String {

    // Apply foreground color
    let fg: String
    switch foreground {
    case .default:
      fg = defaultColor(out, .foreground)
    case .white:
      fg = white(out, .foreground)
    case .green:
      fg = green(out, .foreground)
    case .black:
      fg = black(out, .foreground)
    case .blue:
      fg = blue(out, .foreground)
    case .orange:
      fg = orange(out, .foreground)
    case .pink:
      fg = pink(out, .foreground)
    case .purple:
      fg = purple(out, .foreground)
    case .red:
      fg = red(out, .foreground)
    case .teal:
      fg = teal(out, .foreground)
    case .yellow:
      fg = yellow(out, .foreground)
    }
    // Apply background color
    let bg: String
    switch background {
    case .default:
      bg = defaultColor(fg, .background)
    case .white:
      bg = white(fg, .background)
    case .green:
      bg = green(fg, .background)
    case .black:
      bg = black(fg, .background)
    case .blue:
      bg = blue(fg, .background)
    case .orange:
      bg = orange(fg, .background)
    case .pink:
      bg = pink(fg, .background)
    case .purple:
      bg = purple(fg, .background)
    case .red:
      bg = red(fg, .background)
    case .teal:
      bg = teal(fg, .background)
    case .yellow:
      bg = yellow(fg, .background)
    }
    return bg
  }

  public enum Position {
    case foreground
    case background
  }

  static func yellow(
    _ str: String, _ position: Position = .foreground
  )
    -> ANSIString
  {
    wrap(str, .int(226), position)
  }

  static func green(
    _ str: String, _ position: Position = .foreground
  )
    -> ANSIString
  {
    wrap(str, .int(40), position)
  }

  static func blue(
    _ str: String, _ position: Position = .foreground
  )
    -> ANSIString
  {
    wrap(str, .int(27), position)
  }

  static func pink(
    _ str: String, _ position: Position = .foreground
  )
    -> ANSIString
  {
    wrap(str, .int(201), position)
  }

  static func red(_ str: String, _ position: Position = .foreground) -> ANSIString {
    wrap(str, .int(196), position)
  }

  static func orange(
    _ str: String, _ position: Position = .foreground
  )
    -> ANSIString
  {
    wrap(str, .int(202), position)
  }

  static func purple(
    _ str: String, _ position: Position = .foreground
  )
    -> ANSIString
  {
    wrap(str, .int(129), position)
  }

  static func white(
    _ str: String, _ position: Position = .foreground
  )
    -> ANSIString
  {
    wrap(str, .int(231), position)
  }

  static func black(
    _ str: String, _ position: Position = .foreground
  )
    -> ANSIString
  {
    wrap(str, .int(232), position)
  }

  static func teal(
    _ str: String, _ position: Position = .foreground
  )
    -> ANSIString
  {
    wrap(str, .int(14), position)
  }

  static func defaultColor(
    _ str: String, _ position: Position = .foreground
  )
    -> ANSIString
  {
    wrap(str, .reset, position)
  }

  private static func wrap(
    _ str: String, _ color: TerminalColor, _ position: Position
  )
    -> ANSIString
  {
    switch position {
    case .foreground:
      return foreground(color, str)
    case .background:
      return background(color, str)
    }
  }

  private static func foreground(_ color: TerminalColor, _ str: String) -> ANSIString {
    // https://www.lihaoyi.com/post/BuildyourownCommandLinewithANSIescapecodes.html
    let colorString: String
    switch color {
    case .reset:
      colorString = "\u{001b}[0m"
    case let .basic(basic):
      switch basic {
      case .black:
        colorString = "\u{001b}[30m"
      case .red:
        colorString = "\u{001b}[31m"
      case .green:
        colorString = "\u{001b}[32m"
      case .yellow:
        colorString = "\u{001b}[33m"
      case .blue:
        colorString = "\u{001b}[34m"
      case .magenta:
        colorString = "\u{001b}[35m"
      case .cyan:
        colorString = "\u{001b}[36m"
      case .white:
        colorString = "\u{001b}[37m"
      }
    case let .bright(bright):
      switch bright {
      case .black:
        colorString = "\u{001b}[30;1m"
      case .red:
        colorString = "\u{001b}[31;1m"
      case .green:
        colorString = "\u{001b}[32;1m"
      case .yellow:
        colorString = "\u{001b}[33;1m"
      case .blue:
        colorString = "\u{001b}[34;1m"
      case .magenta:
        colorString = "\u{001b}[35;1m"
      case .cyan:
        colorString = "\u{001b}[36;1m"
      case .white:
        colorString = "\u{001b}[37;1m"
      }
    case let .int(i):
      colorString = "\u{001b}[38;5;\(i % 256)m"
    }
    return colorString + str + "\u{001b}[0m"
  }

  private static func background(_ color: TerminalColor, _ str: String) -> ANSIString {
    // https://www.lihaoyi.com/post/BuildyourownCommandLinewithANSIescapecodes.html
    let colorString: String
    switch color {
    case .reset:
      colorString = "\u{001b}[0m"
    case let .basic(basic):
      switch basic {
      case .black:
        colorString = "\u{001b}[40m"
      case .red:
        colorString = "\u{001b}[41m"
      case .green:
        colorString = "\u{001b}[42m"
      case .yellow:
        colorString = "\u{001b}[43m"
      case .blue:
        colorString = "\u{001b}[44m"
      case .magenta:
        colorString = "\u{001b}[45m"
      case .cyan:
        colorString = "\u{001b}[46m"
      case .white:
        colorString = "\u{001b}[47m"
      }
    case let .bright(bright):
      switch bright {
      case .black:
        colorString = "\u{001b}[40;1m"
      case .red:
        colorString = "\u{001b}[41;1m"
      case .green:
        colorString = "\u{001b}[42;1m"
      case .yellow:
        colorString = "\u{001b}[43;1m"
      case .blue:
        colorString = "\u{001b}[44;1m"
      case .magenta:
        colorString = "\u{001b}[45;1m"
      case .cyan:
        colorString = "\u{001b}[46;1m"
      case .white:
        colorString = "\u{001b}[47;1m"
      }
    case let .int(i):
      colorString = "\u{001b}[48;5;\(i % 256)m"
    }
    return colorString + str + AnsiEscapeCode.reset.rawValue
  }
}
