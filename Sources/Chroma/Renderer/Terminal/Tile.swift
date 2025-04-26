/// Represents one monospaced unit of the screen.
struct Tile: Equatable {
  let symbol: Character
  let fg: Shell.Color
  let bg: Shell.Color

  init(_ symbol: Character = " ") {
    self.symbol = symbol
    self.fg = .default
    self.bg = .default
  }

  init(symbol: Character, fg: Shell.Color, bg: Shell.Color) {
    self.symbol = symbol
    self.fg = fg
    self.bg = bg
  }

  var ascii: String {
    Shell.wrap("\(symbol)", fg, bg)
  }
}
