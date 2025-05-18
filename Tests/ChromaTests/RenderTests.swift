import Testing

@testable import Chroma
@testable import Demo

struct NewRenderer: ElementWalker {
  var currentHash: Hash = ""
  var orientation: Orientation {
    didSet {
      // Gets called before and after each orientation change.
      print("HERE")
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

  mutating func beforeGroup(childrenCount: Int) {}

  mutating func afterGroup(ourHash: Hash) {}

  mutating func beforeChild() -> Bool { false }

  mutating func afterChild(
    nextChildHash: Hash,
    prevChildHash: Hash,
    index: Int, childCount: Int
  ) -> Bool { false }

  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    switch self.orientation {
    case .horizontal:
      guard tiles[0].count >= width + text.count else {
        print("Will not fit")
        return
      }
      for (i, char) in text.enumerated() {
        tiles[0][width + i] = Tile(symbol: char, fg: fg, bg: bg)
      }
      width += text.count
    case .vertical:
      for (i, char) in text.enumerated() {
        tiles[height][i] = Tile(symbol: char, fg: fg, bg: bg)
      }
      height += 1
    }
  }
}

@MainActor
@Suite("Renderer Tests")
struct RendererTests {

  @Test func testHorizontal() async throws {
    let h = 1
    let w = 9
    let block = HTest()
    var parser = NewRenderer(height: h, width: w)
    block.parseTree(action: false, &parser)
    let expectedText: String = #"""
      HelloZane
      """#
    let window = Window(expectedText, width: w, height: h)
    #expect(window.tiles == parser.tiles)
    print(parser._raw)
  }

  @Test func testVertical() async throws {
    let h = 2
    let w = 5
    let block = BasicTupleText()
    var parser = NewRenderer(height: h, width: w)
    block.parseTree(action: false, &parser)
    let expectedText: String = #"""
      Hello
      Zane%
      """#
    let window = Window(expectedText, width: w, height: h)
    #expect(window.tiles == parser.tiles)
  }
}
