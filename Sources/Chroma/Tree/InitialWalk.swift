struct InitialWalk: L2HashWalker {

  private var first: Bool = true
  private(set) var state: BlockState
  var currentHash: Hash

  init(state: BlockState) {
    self.state = state
    self.currentHash = hash(contents: "0")
  }

  mutating func beforeGroup(_ group: [L2Element]) {
    setFirstSelection()
  }

  mutating func afterGroup(_ group: [L2Element]) {
    // ignored
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
