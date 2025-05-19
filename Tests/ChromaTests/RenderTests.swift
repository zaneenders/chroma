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

  @Test func testHTest2() async throws {
    let h = 2
    let w = 9
    let block = HTest2()
    var parser = NewRenderer(height: h, width: w)
    block.parseTree(action: false, &parser)
    let expectedText: String = #"""
      HelloZane
      WasHere%%
      """#
    let window = Window(expectedText, width: w, height: h)
    #expect(window.tiles == parser.tiles)
  }
}
