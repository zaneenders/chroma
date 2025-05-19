struct ElementRender: ElementWalker {
  let state: BlockState
  var currentHash: Hash
  var orientation: Orientation
  private var groupHeight = 0
  private var groupWidth = 0
  private var currentWidth = 0
  private var currentHeight = 0
  /*
  Well this is where our nested groups push and pop things off the stack.
  
  Well better we know how much space is available and consumed at this point.
  */
  mutating func pushNewGroup() {
    groupHeight = currentHeight
    groupWidth = 0
  }
  mutating func popGroup() {
    switch orientation {
    case .horizontal:
      currentWidth = max(groupWidth, currentWidth)
      currentHeight = max(groupHeight + 1, currentHeight)
    case .vertical:
      currentWidth = max(groupWidth, currentWidth)
      currentHeight = max(groupHeight, currentHeight)
    }
  }
  private let fg: Shell.Color = .blue
  private let bg: Shell.Color = .green
  private var seenSelected: Bool = false
  private let width: Int
  private let height: Int

  init(state: BlockState, width: Int, height: Int) {
    self.height = height
    self.width = width
    self.state = state
    self.tiles = Array(
      repeating: Array(repeating: Tile(), count: width),
      count: height)
    self.orientation = .vertical
    self.currentHash = hash(contents: "\(0)")
  }
  var tiles: [[Tile]]

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

  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    // This HACK needs to come before we update seenSelected for now.
    switch orientation {
    case .horizontal:
      ()
    case .vertical:
      // HACK for vertical scrolling.
      if groupHeight >= height {
        if !seenSelected {
          groupHeight -= 1  // Override the last row.
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
    }
    let fg: Shell.Color
    let bg: Shell.Color
    if self.state.selected == currentHash {
      seenSelected = true
      fg = .yellow
      bg = .purple
    } else {
      fg = .blue
      bg = .green
    }
    switch self.orientation {
    case .horizontal:
      guard tiles[0].count >= groupWidth + text.count else {
        print("Will not fit")
        return
      }
      for (i, char) in text.enumerated() {
        tiles[groupHeight][groupWidth + i] = Tile(symbol: char, fg: fg, bg: bg)
      }
      groupWidth += text.count
    case .vertical:
      for (i, char) in text.enumerated() {
        tiles[groupHeight][groupWidth + i] = Tile(symbol: char, fg: fg, bg: bg)
      }
      groupHeight += 1
    }
  }
}
