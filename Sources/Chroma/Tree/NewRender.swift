struct NewRenderer: ElementWalker {
  var currentHash: Hash = ""
  var orientation: Orientation
  private var groupHeight = 0
  private var groupWidth = 0
  /*
    Well this is where our nested groups push and pop things off the stack.
  
    Well better we know how much space is available and consumed at this point.
    */
  mutating func pushNewGroup() {
    groupHeight = height
    groupWidth = 0
  }
  mutating func popGroup() {
    switch orientation {
    case .horizontal:
      width = max(groupWidth, width)
      height = max(groupHeight + 1, height)
    case .vertical:
      width = max(groupWidth, width)
      height = max(groupHeight, height)
    }
  }
  private var width = 0
  private var height = 0
  private let fg: Shell.Color = .blue
  private let bg: Shell.Color = .green
  init(height: Int, width: Int) {
    self.tiles = Array(
      repeating: Array(repeating: Tile(symbol: "%", fg: fg, bg: bg), count: width),
      count: height)
    self.orientation = .vertical
  }
  var tiles: [[Tile]]

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
