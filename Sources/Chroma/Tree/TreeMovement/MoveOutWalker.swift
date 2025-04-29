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

  mutating func beforeGroup(_ group: [any Block]) {
    appendPath(siblings: group.count - 1)
  }
  mutating func beforeChild() -> Bool { false }
  mutating func afterChild(nextChildHash: Hash, prevChildHash: Hash, index: Int, childCount: Int) -> Bool {
    false
  }
  mutating func afterGroup(ourHash: Hash, _ group: [any Block]) {
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
    path.removeLast()
  }
  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    appendPath(siblings: 0)
    // No updates to be made here best case found selected.
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
