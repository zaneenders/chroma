@testable import Chroma

struct TestRenderer: Renderer {
  var selected = ""
  var previousWalker: TestWalker = TestWalker(state: BlockState())

  mutating func view(_ block: borrowing some Block, with state: BlockState) {
    selected = state.selected ?? ""
    var walker = TestWalker(state: state)
    walker.textObjects = [:]
    block.parseTree(action: false, &walker)
    previousWalker = walker
  }
}

struct TestWalker: L2ElementWalker {

  // Set by the visitor
  var currentHash: Hash
  let state: BlockState
  var blockObjects: [Hash: String]

  var textObjects: [Hash: String] = [:]
  init(state: BlockState) {
    self.state = state
    self.currentHash = hash(contents: "\(0)")
    self.blockObjects = [:]
  }

  mutating func beforeGroup(childrenCount: Int) {}
  mutating func beforeChild() -> Bool { false }
  mutating func afterChild(nextChildHash: Hash, prevChildHash: Hash, index: Int, childCount: Int) -> Bool { false }
  mutating func afterGroup(ourHash: Hash) {}

  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    leafNode(text)
  }

  mutating func leafNode(_ text: String) {
    if currentHash == self.state.selected {
      textObjects[currentHash] = "[\(text)]"
    } else {
      textObjects[currentHash] = text
    }
  }
}
