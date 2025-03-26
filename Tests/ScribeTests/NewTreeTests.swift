import Testing

@testable import Demo
@testable import Scribe

@MainActor  // UI Block test run on main thread.
@Suite("New Tree Tests")
struct NewTreeTests {

  @Test func treeEntry() async throws {
    let block = Entry()
    let tree = block.toL1Element()
    var parser = L1ElementRender(state: BlockState(), width: 80, height: 24)
    parser.walk(tree)
    let expectedText = #"""
      Hello, I am Scribe.
      Zane was here :0
      Job running: ready
      Nested[text: Hello]
      """#
    let window = Window(expectedText, width: 80, height: 24)
    #expect(window.tiles == parser.tiles)
  }

  @Test func treeAll() async throws {
    let block = All()
    let tree = block.toL1Element()
    var parser = L1ElementRender(state: BlockState(), width: 80, height: 24)
    parser.walk(tree)
    let expectedText = #"""
      Button
      A
      Zane
      Was
      Here
      """#
    let window = Window(expectedText, width: 80, height: 24)
    #expect(window.tiles == parser.tiles)
  }

  @Test func treeOptionalBlock() async throws {
    let block = OptionalBlock()
    let tree = block.toL1Element()
    var parser = L1ElementRender(state: BlockState(), width: 80, height: 24)
    parser.walk(tree)
    let expectedText = #"""
      OptionalBlock(idk: Optional("Hello"))
      Hello
      """#
    // print(parser._raw)
    let window = Window(expectedText, width: 80, height: 24)
    #expect(window.tiles == parser.tiles)
  }

  @Test func treeBasicTupleText() async throws {
    let block = BasicTupleText()
    let tree = block.toL1Element()
    var parser = L1ElementRender(state: BlockState(), width: 80, height: 24)
    parser.walk(tree)
    let expectedText = #"""
      Hello
      Zane
      """#
    let window = Window(expectedText, width: 80, height: 24)
    #expect(window.tiles == parser.tiles)
  }

  @Test func treeSelectionBlock() async throws {
    let block = SelectionBlock()
    let tree = block.toL1Element()
    var parser = L1ElementRender(state: BlockState(), width: 80, height: 24)
    parser.walk(tree)
    let expectedText = #"""
      Hello
      Zane
      was
      here
      0
      1
      2
      """#
    let window = Window(expectedText, width: 80, height: 24)
    #expect(window.tiles == parser.tiles)
  }

  @Test func treeAsyncUpdateStateUpdate() async throws {
    let block = AsyncUpdateStateUpdate()
    let tree = block.toL1Element()
    var parser = L1ElementRender(state: BlockState(), width: 80, height: 24)
    parser.walk(tree)
    let expectedText = #"""
      ready
      """#
    let window = Window(expectedText, width: 80, height: 24)
    #expect(window.tiles == parser.tiles)
  }
}

struct Window {
  let height: Int
  let width: Int
  var count = 0

  var tiles: [[Tile]]

  init(_ contents: String, width: Int, height: Int) {
    self.tiles = Array(repeating: Array(repeating: Tile(), count: width), count: height)
    self.height = height
    self.width = width
    let lines = contents.split(separator: "\n")
    for (i, line) in lines.enumerated() {
      count = i
      place("\(line)", i, selected: false)
    }
  }

  private mutating func place(_ text: String, _ index: Int, selected: Bool) {
    // TODO why even take the index in if we aren't going to use it.
    let fg: Chroma.Color
    let bg: Chroma.Color
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
        Log.error("Frame width exceeded with \(text)")
        break place_loop
      }
      guard char != "\n" else {
        Log.error("Found newline in word \(text)")
        break place_loop
      }
      guard count < height else {
        Log.error("Too many rows \(text)")
        break place_loop
      }
      tiles[count][x + i] = Tile(symbol: char, fg: fg, bg: bg)
      placed += 1
    }
    x += placed
  }
}
