struct ActionWalker: L2HashWalker {

  private(set) var state: BlockState
  private var input: AsciiKeyCode
  var currentHash: Hash = hash(contents: "0")

  init(state: BlockState, input: AsciiKeyCode) {
    self.state = state
    self.input = input
  }

  mutating func beforeGroup(_ group: [L2Element]) {}

  mutating func afterGroup(_ group: [L2Element]) {}

  mutating func walkText(_ text: String, _ handler: InputHandler?) {
    Log.debug("\(#function): \(currentHash), \(state.selected)")
    runBinding(handler)
  }

  private func runBinding(_ handler: InputHandler?) {
    let selected = self.state.selected == currentHash
    if let handler {
      handler(input, selected)
    }
  }
}
