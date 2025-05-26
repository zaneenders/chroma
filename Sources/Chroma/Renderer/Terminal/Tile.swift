import ChromaShell

/// Represents one monospaced unit of the screen.
struct Tile: Equatable {
  let symbol: Character
  let fg: ChromaShell.Color
  let bg: ChromaShell.Color

  init(_ symbol: Character = " ") {
    self.symbol = symbol
    self.fg = .default
    self.bg = .default
  }

  init(symbol: Character, fg: ChromaShell.Color, bg: ChromaShell.Color) {
    self.symbol = symbol
    self.fg = fg
    self.bg = bg
  }

  var ascii: String {
    ChromaShell.wrap("\(symbol)", fg, bg)
  }
}
