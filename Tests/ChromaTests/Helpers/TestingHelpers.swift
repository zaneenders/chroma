@testable import Chroma

func enableTestLogging(write_to_file: Bool = true) {
  enableLogging(
    file_path: "chroma.log", logLevel: .trace, tracing: false, write_to_file: write_to_file)
  clearLog("chroma.log")
}

struct Window {
  let height: Int
  let width: Int

  var tiles: [[Tile]]

  init(_ contents: String, width: Int, height: Int) {
    self.tiles = Array(repeating: Array(repeating: Tile(), count: width), count: height)
    self.height = height
    self.width = width
    let lines = contents.split(separator: "\n")
    for (i, line) in lines.enumerated() {
      place("\(line)", i, selected: false)
    }
  }

  private mutating func place(_ text: String, _ index: Int, selected: Bool) {
    let fg: Shell.Color
    let bg: Shell.Color
    if selected {
      fg = .yellow
      bg = .purple
    } else {
      fg = .blue
      bg = .green
    }
    var placed = 0
    var x = 0
    place_loop: for (i, char) in text.enumerated() {
      guard x + i < width else {
        _ChromaLog.error("Frame width exceeded with \(text)")
        break place_loop
      }
      guard char != "\n" else {
        _ChromaLog.error("Found newline in word \(text)")
        break place_loop
      }
      guard index < height else {
        _ChromaLog.error("Too many rows \(text)")
        break place_loop
      }
      tiles[index][x + i] = Tile(symbol: char, fg: fg, bg: bg)
      placed += 1
    }
    x += placed
  }
}
