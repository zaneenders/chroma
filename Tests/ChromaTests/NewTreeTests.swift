import Testing

@testable import Chroma
@testable import Demo

// Note none of these test selection.
@MainActor  // UI Block test run on main thread.
@Suite("New Tree Tests", .disabled())
struct NewTreeTests {

  @Test func treeEntry() async throws {
    let block = Entry()
    var parser = ElementRender(state: BlockState(), width: 80, height: 24)
    block.parseTree(action: false, &parser)
    let expectedText = #"""
      Hello, I am Chroma.
      Zane was here :0
      Job running: ready
      Nested[text: Hello]
      """#
    let window = Window(expectedText, width: 80, height: 24)
    #expect(window.tiles == parser.tiles)
  }

  @Test func treeAll() async throws {
    let block = All()
    var parser = ElementRender(state: BlockState(), width: 80, height: 24)
    block.parseTree(action: false, &parser)
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
    var parser = ElementRender(state: BlockState(), width: 80, height: 24)
    block.parseTree(action: false, &parser)
    let expectedText = #"""
      OptionalBlock(idk: Optional("Hello"))
      Hello
      """#
    let window = Window(expectedText, width: 80, height: 24)
    #expect(window.tiles == parser.tiles)
  }

  @Test func treeBasicTupleText() async throws {
    let block = BasicTupleText()
    var parser = ElementRender(state: BlockState(), width: 80, height: 24)
    block.parseTree(action: false, &parser)
    let expectedText = #"""
      Hello
      Zane
      """#
    let window = Window(expectedText, width: 80, height: 24)
    #expect(window.tiles == parser.tiles)
  }

  @Test func treeSelectionBlock() async throws {
    let block = SelectionBlock()
    var parser = ElementRender(state: BlockState(), width: 80, height: 24)
    block.parseTree(action: false, &parser)
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
        Log.error("Frame width exceeded with \(text)")
        break place_loop
      }
      guard char != "\n" else {
        Log.error("Found newline in word \(text)")
        break place_loop
      }
      guard index < height else {
        Log.error("Too many rows \(text)")
        break place_loop
      }
      tiles[index][x + i] = Tile(symbol: char, fg: fg, bg: bg)
      placed += 1
    }
    x += placed
  }
}
