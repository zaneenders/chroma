protocol L2SelectionWalker: L2HashWalker {
  var state: BlockState { get }
  var isSelected: Bool { get set }
  mutating func leafNode(_ text: String)
}

extension L2SelectionWalker {

  private mutating func updateSelected() {
    if !isSelected {
      isSelected = state.selected == currentHash
    }
  }

  private mutating func resetSelected() {
    if currentHash == state.selected {
      isSelected = false
    }
  }

  mutating func beforeGroup(_ group: [L2Element]) {
    updateSelected()
  }

  mutating func afterGroup(_ group: [L2Element]) {
    resetSelected()
  }

  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    updateSelected()
    leafNode(text)
    resetSelected()
  }
}
