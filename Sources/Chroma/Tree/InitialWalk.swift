struct InitialWalk: L2ElementWalker {

  private var first: Bool = true
  private(set) var state: BlockState
  var currentHash: Hash

  init(state: BlockState) {
    self.state = state
    self.currentHash = hash(contents: "0")
  }

  mutating func beforeGroup(_ group: [any Block]) {
    setFirstSelection()
  }

  mutating func afterGroup(ourHash: Hash, _ group: [any Block]) {}
  mutating func beforeChild() -> Bool { false }
  mutating func afterChild(nextChildHash: Hash, index: Int, childCount: Int) -> Bool {
    false
  }
  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    setFirstSelection()
  }

  private mutating func setFirstSelection() {
    if first {
      self.state.selected = currentHash
      first = false
    }
  }
}
