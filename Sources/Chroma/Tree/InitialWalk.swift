struct InitialWalk: ElementWalker {

  private var first: Bool = true
  private(set) var state: BlockState
  var currentHash: Hash
  var orientation: Orientation

  init(state: BlockState) {
    self.state = state
    self.currentHash = hash(contents: "0")
    self.orientation = .vertical
  }

  mutating func beforeGroup(childrenCount: Int) {
    setFirstSelection()
  }
  mutating func beforeChild() -> Bool { false }
  mutating func afterChild(nextChildHash: Hash, prevChildHash: Hash, index: Int, childCount: Int) -> Bool {
    false
  }
  mutating func afterGroup(ourHash: Hash) {}
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
