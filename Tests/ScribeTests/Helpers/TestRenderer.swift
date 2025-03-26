@testable import Scribe

struct TestRenderer: Renderer {
  var selected = ""
  var previousWalker: TestWalker = TestWalker(state: BlockState())

  mutating func view(_ block: borrowing some Block, with state: BlockState) {
    selected = state.selected ?? ""
    var walker = TestWalker(state: state)
    walker.textObjects = [:]
    walker.walk(block.toL1Element())
    previousWalker = walker
  }
}

extension TestRenderer {
  struct TestWalker: L1SelectionWalker {

    // Set by the visitor
    var currentHash: Hash
    let state: BlockState
    var blockObjects: [Hash: String]

    var textObjects: [Hash: String] = [:]
    var isSelected: Bool = false
    init(state: BlockState) {
      self.state = state
      self.currentHash = hash(contents: "\(0)")
      self.blockObjects = [:]
    }

    mutating func leafNode(_ text: String) {
      if isSelected {
        textObjects[currentHash] = "[\(text)]"
      } else {
        textObjects[currentHash] = text
      }
    }
  }
}
