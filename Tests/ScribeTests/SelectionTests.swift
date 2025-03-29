import Testing

@testable import Demo
@testable import Scribe

@MainActor  // UI Block test run on main thread.
@Suite("Selection Tests")
// NOTE: Keep ordered by Demo then BlockSnippets
struct SelectionTests {

  @Test func selectEntry() async throws {
    let window = TerminalWindow {
      Entry()
    }.environment(Mode())
    var container = ScribeController(window.entry)
    var renderer = TestRenderer()
    container.expectState(
      &renderer,
      expected: [
        "[Hello, I am Scribe.]", "[Job running: ready]", "[Nested[text: Hello]]",
        "[Zane was here :0]",
      ])

    container.moveIn()
    container.expectState(
      &renderer,
      expected: [
        "[Hello, I am Scribe.]", "Job running: ready", "Nested[text: Hello]", "Zane was here :0",
      ])

    container.action(.lowercaseI)
    container.expectState(
      &renderer,
      expected: [
        "Zane was here :0", "Nested[text: Hello#]", "[Hello, I am Scribe.!]", "Job running: ready",
      ])

    container.moveDown()
    container.expectState(
      &renderer,
      expected: [
        "[Zane was here :0]", "Nested[text: Hello#]", "Hello, I am Scribe.!", "Job running: ready",
      ])

    container.action(.lowercaseE)
    container.expectState(
      &renderer,
      expected: [
        "Job running: ready", "[Zane was here :1]", "Nested[text: Hello#]", "Hello, I am Scribe.!",
        "0",
      ])
    container.moveDown()
    container.expectState(
      &renderer,
      expected: [
        "Zane was here :1", "[Job running: ready]", "Nested[text: Hello#]", "Hello, I am Scribe.!",
        "0",
      ])
    container.action(.lowercaseI)
    container.expectState(
      &renderer,
      expected: [
        "Zane was here :1", "[Job running: running]", "Nested[text: running]",
        "Hello, I am Scribe.!", "0",
      ])
    try await Task.sleep(for: .seconds(0.5))
    container.expectState(
      &renderer,
      expected: [
        "Zane was here :1", "[Job running: running]", "Nested[text: running]",
        "Hello, I am Scribe.!", "0",
      ])
    try await Task.sleep(for: .seconds(1))
    container.expectState(
      &renderer,
      expected: [
        "Zane was here :1", "[Job running: ready]", "Nested[text: ready]", "Hello, I am Scribe.!",
        "0",
      ])
    container.moveUp()
    container.expectState(
      &renderer,
      expected: [
        "[Zane was here :1]", "Job running: ready", "Nested[text: ready]", "Hello, I am Scribe.!",
        "0",
      ])

  }

  @Test func selectEntryMoveToNested() async throws {
    let window = TerminalWindow {
      Entry()
    }.environment(Mode())
    var container = ScribeController(window.entry)
    var renderer = TestRenderer()
    container.moveIn()
    container.moveIn()
    container.moveDown()
    container.moveDown()
    container.moveDown()
    container.expectState(
      &renderer,
      expected: [
        "Zane was here :0", "Job running: ready", "[Nested[text: Hello]]", "Hello, I am Scribe.",
      ])
    container.moveUp()
    container.expectState(
      &renderer,
      expected: [
        "Zane was here :0", "[Job running: ready]", "Nested[text: Hello]", "Hello, I am Scribe.",
      ])
  }

  @Test func selectAll() async throws {
    let block = All()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(&renderer, expected: ["[A]", "[Button]", "[Here]", "[Was]", "[Zane]"])
    // Move in
    container.moveIn()

    container.moveIn()
    container.expectState(&renderer, expected: ["[Button]", "A", "Zane", "Was", "Here"])
    container.action(.lowercaseI)
    container.expectState(&renderer, expected: ["[Button]", "B", "Zane", "Was", "Here"])
  }

  @Test func selectOptionalBlock() async throws {
    let block = OptionalBlock()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(
      &renderer, expected: ["[Hello]", "[OptionalBlock(idk: Optional(\"Hello\"))]"])
  }

  // Test up and down logic.
  @Test func selectBasicTupleBindedText() async throws {
    let block = BasicTupleBindedText()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(&renderer, expected: ["[Hello]", "[Zane]", "[Enders]"])
    container.moveIn()
    container.moveIn()
    container.moveDown()
    container.expectState(&renderer, expected: ["Hello", "[Zane]", "Enders"])
    container.moveUp()
    container.expectState(&renderer, expected: ["[Hello]", "Zane", "Enders"])
    container.moveDown()
    container.moveDown()
    container.expectState(&renderer, expected: ["Hello", "Zane", "[Enders]"])
    container.moveUp()
    container.expectState(&renderer, expected: ["Hello", "[Zane]", "Enders"])
    container.moveUp()
    container.expectState(&renderer, expected: ["[Hello]", "Zane", "Enders"])
  }

  @Test func selectBasicTupleText() async throws {
    let block = BasicTupleText()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(&renderer, expected: ["[Hello]", "[Zane]"])
  }

  @Test func selectBasicTupleTextMoveIn() async throws {
    let block = BasicTupleText()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(&renderer, expected: ["[Hello]", "[Zane]"])
    container.moveIn()
    container.expectState(&renderer, expected: ["[Hello]", "Zane"])
    container.moveIn()
    container.expectState(&renderer, expected: ["[Hello]", "Zane"])
  }

  @Test func selectBasicTupleTextMoveInAndOut() async throws {
    let block = BasicTupleText()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(&renderer, expected: ["[Hello]", "[Zane]"])
    container.moveIn()
    container.moveIn()
    container.expectState(&renderer, expected: ["[Hello]", "Zane"])
    container.moveOut()
    container.expectState(&renderer, expected: ["[Hello]", "[Zane]"])
    container.moveOut()
    container.expectState(&renderer, expected: ["[Hello]", "[Zane]"])
  }

  @Test func selectBasicTupleTextMoveInDownOut() async throws {
    let block = BasicTupleText()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(&renderer, expected: ["[Hello]", "[Zane]"])
    container.moveIn()
    container.moveIn()
    container.expectState(&renderer, expected: ["[Hello]", "Zane"])
    container.moveDown()
    container.expectState(&renderer, expected: ["Hello", "[Zane]"])
    container.moveOut()
    container.expectState(&renderer, expected: ["[Hello]", "[Zane]"])
  }

  @Test func selectBasicTupleTextMoveInDownUpOut() async throws {
    let block = BasicTupleText()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(&renderer, expected: ["[Hello]", "[Zane]"])
    container.moveIn()
    container.moveIn()
    container.expectState(&renderer, expected: ["[Hello]", "Zane"])
    container.moveDown()
    container.expectState(&renderer, expected: ["Hello", "[Zane]"])
    container.moveUp()
    container.expectState(&renderer, expected: ["[Hello]", "Zane"])
    container.moveOut()
    container.expectState(&renderer, expected: ["[Hello]", "[Zane]"])
  }

  @Test func selectSelectionBlockDontMoveDown() async throws {
    let block = SelectionBlock()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(
      &renderer, expected: ["[0]", "[1]", "[2]", "[Hello]", "[Zane]", "[here]", "[was]"])

    // Move Down
    container.moveDown()
    container.expectState(
      &renderer, expected: ["[0]", "[1]", "[2]", "[Hello]", "[Zane]", "[here]", "[was]"])
  }

  @Test func selectSelectionBlock() async throws {
    let block = SelectionBlock()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(
      &renderer, expected: ["[0]", "[1]", "[2]", "[Hello]", "[Zane]", "[here]", "[was]"])

    container.moveIn()
    container.expectState(&renderer, expected: ["0", "1", "2", "Zane", "[Hello]", "here", "was"])

    container.moveIn()
    container.expectState(&renderer, expected: ["0", "1", "2", "Zane", "[Hello]", "here", "was"])

    container.moveIn()
    container.expectState(&renderer, expected: ["0", "1", "2", "Zane", "[Hello]", "here", "was"])

    container.moveDown()
    container.expectState(&renderer, expected: ["0", "1", "2", "[Zane]", "Hello", "here", "was"])

    container.moveUp()
    container.expectState(&renderer, expected: ["0", "1", "2", "Zane", "[Hello]", "here", "was"])

    container.moveDown()
    container.expectState(&renderer, expected: ["0", "1", "2", "[Zane]", "Hello", "here", "was"])

    container.moveDown()
    container.expectState(&renderer, expected: ["0", "1", "2", "Zane", "Hello", "here", "[was]"])

    container.moveDown()
    container.expectState(&renderer, expected: ["0", "1", "2", "Zane", "Hello", "[here]", "was"])

    container.moveDown()
    container.expectState(&renderer, expected: ["[0]", "1", "2", "Zane", "Hello", "here", "was"])

    container.moveDown()
    container.expectState(&renderer, expected: ["0", "[1]", "2", "Zane", "Hello", "here", "was"])

    container.moveDown()
    container.expectState(&renderer, expected: ["0", "1", "[2]", "Zane", "Hello", "here", "was"])

    container.moveDown()
    container.expectState(&renderer, expected: ["0", "1", "[2]", "Zane", "Hello", "here", "was"])

    container.moveDown()
    container.expectState(&renderer, expected: ["0", "1", "[2]", "Zane", "Hello", "here", "was"])

    container.moveUp()
    container.expectState(&renderer, expected: ["0", "[1]", "2", "Zane", "Hello", "here", "was"])

    container.moveOut()
    container.expectState(
      &renderer, expected: ["[0]", "[1]", "[2]", "[Hello]", "[Zane]", "[here]", "[was]"])

    container.moveOut()
    container.expectState(
      &renderer, expected: ["[0]", "[1]", "[2]", "[Hello]", "[Zane]", "[here]", "[was]"])

    container.moveOut()
    container.expectState(
      &renderer, expected: ["[0]", "[1]", "[2]", "[Hello]", "[Zane]", "[here]", "[was]"])
  }

  @Test func selectAsyncUpdateStateUpdate() async throws {

    let firstPause = AsyncUpdateStateUpdate.delay / 2
    let secondPause = AsyncUpdateStateUpdate.delay

    let block = AsyncUpdateStateUpdate()
    var container = ScribeController(block)
    var renderer = TestRenderer()
    container.expectState(&renderer, expected: ["[ready]"])

    // Move in
    container.moveIn()
    container.expectState(&renderer, expected: ["[ready]"])

    // Action
    container.action(.lowercaseI)
    container.expectState(&renderer, expected: ["[running]"])

    try await Task.sleep(for: .milliseconds(firstPause))
    container.expectState(&renderer, expected: ["[running]"])

    try await Task.sleep(for: .milliseconds(secondPause))
    container.expectState(&renderer, expected: ["[ready]"])
  }

  @Test func selectNestedAsyncUpdateStateUpdate() async throws {

    let firstPause = AsyncUpdateStateUpdate.delay / 2
    let secondPause = AsyncUpdateStateUpdate.delay

    var container = ScribeController(NestedAsyncUpdate())
    var renderer = TestRenderer()
    container.expectState(&renderer, expected: ["[ready]"])

    // Move in
    container.moveIn()
    container.expectState(&renderer, expected: ["[ready]"])

    // Action
    container.action(.lowercaseI)
    container.expectState(&renderer, expected: ["[running]"])

    try await Task.sleep(for: .milliseconds(firstPause))
    container.expectState(&renderer, expected: ["[running]"])

    try await Task.sleep(for: .milliseconds(secondPause))
    container.expectState(&renderer, expected: ["[ready]"])
  }
}

// Helper functions to make creating test easier.
extension ScribeController {
  mutating func moveUp() {
    up()
  }
  mutating func moveDown() {
    down()
  }
  mutating func moveOut() {
    out()
  }
  mutating func moveIn() {
    `in`()
  }

  mutating func expectState(_ renderer: inout TestRenderer, expected: [String]) {
    self.observe(with: &renderer)
    let output = renderer.previousWalker.textObjects.map { $0.value }
    #expect(output.sorted() == expected.sorted())
  }

  // Helper for creating expected arrays
  mutating func printState(_ renderer: inout TestRenderer) {
    self.observe(with: &renderer)
    let output = renderer.previousWalker.textObjects.map { $0.value }
    print(output)
  }
}
