import Testing

@testable import Chroma
@testable import Demo

@MainActor
@Suite("Navigation Testing")
struct name {
  @Test func testNav() async throws {
    let block = TestNav()
    var container = ChromaController(block)
    var renderer = TestRenderer()
    container.expectState(
      &renderer,
      expected: ["Top", "Bottom", "Bottom Content"])
  }
}
