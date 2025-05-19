import Testing

@testable import Chroma
@testable import Demo

@MainActor
@Suite("Renderer Tests")
struct RendererTests {

  @Test func testHorizontal() async throws {
    let h = 1
    let w = 9
    let block = HTest()
    var parser = ElementRender(state: BlockState(), width: w, height: h)
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
    var parser = ElementRender(state: BlockState(), width: w, height: h)
    block.parseTree(action: false, &parser)
    let expectedText: String = #"""
      Hello
      Zane
      """#
    let window = Window(expectedText, width: w, height: h)
    #expect(window.tiles == parser.tiles)
  }

  @Test func testHTest2() async throws {
    let h = 2
    let w = 9
    let block = HTest2()
    var parser = ElementRender(state: BlockState(), width: w, height: h)
    block.parseTree(action: false, &parser)
    let expectedText: String = #"""
      HelloZane
      WasHere
      """#
    let window = Window(expectedText, width: w, height: h)
    #expect(window.tiles == parser.tiles)
  }

  @Test func treeEntry() async throws {
    let block = Entry()
    var parser = ElementRender(state: BlockState(), width: 80, height: 24)
    block.parseTree(action: false, &parser)
    let expectedText = #"""
      Hello, I am Chroma.
      Zane was here :0
      Job running: ready
      Nested[text: Hello, I am Chroma.]
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
