struct L2ElementRender: L2ElementWalker {
  var currentHash: Hash
  var width: Int
  var height: Int
  var tiles: [[Tile]]
  var count = 0
  let state: BlockState
  private var seenSelected: Bool = false

  init(state: BlockState, width: Int, height: Int) {
    self.state = state
    self.height = height
    self.width = width
    self.tiles = Array(
      repeating: Array(repeating: Tile(), count: width),
      count: height)
    currentHash = hash(contents: "\(0)")
  }

  var ascii: String {
    var out = ""
    for row in tiles {
      var line = ""
      for rune in row {
        line += rune.ascii
      }
      line += "\n"
      out += line
    }
    out.removeLast()  // remove last newline.
    return out
  }

  // Used for helping create test.
  // Doesn't use .ascii
  var _raw: String {
    var out = ""
    for row in tiles {
      var line = ""
      for rune in row {
        line += "\(rune.symbol)"
      }
      line += "\n"
      out += line
    }
    out.removeLast()  // remove last newline.
    return out
  }

  mutating func beforeGroup(_ group: [any Block]) {}
  mutating func afterGroup(ourHash: Hash, _ group: [any Block]) {}
  mutating func beforeChild() -> Bool { false }
  mutating func afterChild(nextChildHash: Hash, index: Int, childCount: Int) -> Bool {
    false
  }
  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    leafNode(text)
  }

  mutating func leafNode(_ text: String) {
    // This "rendering" logic is dumb but lets get it working first.
    if count >= height {
      if !seenSelected {
        count -= 1  // Override the last row.
        for (i, _) in tiles.enumerated() {
          if i < tiles.count - 1 {
            tiles[i] = tiles[i + 1]
          }
        }
        tiles[tiles.count - 1] = Array(repeating: Tile(), count: width)
      } else {
        Log.error("Too many rows \(text)")
        return
      }
    }
    let isSelected = self.state.selected == currentHash
    place(text, count, selected: isSelected)
    count += 1
  }

  private mutating func place(_ text: String, _ index: Int, selected: Bool) {
    let fg: Shell.Color
    let bg: Shell.Color
    if selected {
      seenSelected = true
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
        Log.error("Frame width exceeded with \(text)")
        break place_loop
      }
      guard char != "\n" else {
        Log.error("Found newline in word \(text)")
        break place_loop
      }
      tiles[index][x + i] = Tile(symbol: char, fg: fg, bg: bg)
      placed += 1
    }
    x += placed
  }
}
