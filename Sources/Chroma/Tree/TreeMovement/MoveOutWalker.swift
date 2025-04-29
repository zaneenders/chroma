struct MoveOutWalker: L2ElementWalker {

  enum State {
    case findingSelected
    case foundSelected
    case selectionUpdated
  }

  private let startingSelection: Hash
  private(set) var state: BlockState
  var currentHash: Hash = hash(contents: "0")
  var mode: State = .findingSelected
  private var path: [SelectedPathNode] = []
  private var selectedDepth = 0

  init(state: BlockState) {
    self.state = state
    self.startingSelection = state.selected!
    Log.debug("\(self.startingSelection)")
  }

  mutating func beforeGroup(_ group: [any Block]) {}
  mutating func afterGroup(_ group: [any Block]) {}
  mutating func beforeChild() {}
  mutating func afterChild() -> Bool {
    false
  }
  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    appendPath(siblings: 0)
    // No updates to be made here best case found selected.
    path.removeLast()
  }

  mutating func beforeGroup(_ group: [L2Element]) {
    appendPath(siblings: group.count - 1)
  }

  mutating func walkGroup(_ group: [L2Element]) {
    let ourHash = currentHash
    beforeGroup(group)
    for (index, element) in group.enumerated() {
      currentHash = hash(contents: "\(ourHash)\(#function)\(index)")
      switch element {
      case .group(let innerGroup):
        walkGroup(innerGroup)
      case let .text(txt, binding):
        walkText(txt, binding)
      }
    }
    switch mode {
    case .findingSelected:
      ()
    case .foundSelected:
      if path.count < selectedDepth {
        // we are below the layer we were
        state.selected = ourHash
        self.mode = .selectionUpdated
      }
    case .selectionUpdated:
      ()
    }
    currentHash = ourHash
    afterGroup(group)
  }

  mutating func afterGroup(_ group: [L2Element]) {
    path.removeLast()
  }

  private mutating func appendPath(siblings: Int) {
    if atSelected {
      mode = .foundSelected
      path.append(.selected)
      selectedDepth = path.count
    } else {
      path.append(.layer(siblings: siblings))
    }
  }

  private var atSelected: Bool {
    startingSelection == currentHash
  }
}
