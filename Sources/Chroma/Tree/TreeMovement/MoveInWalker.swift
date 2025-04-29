struct MoveInWalker: L2ElementWalker {

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
    switch mode {
    case .findingSelected:
      ()
    case .foundSelected:
      if path.count > selectedDepth {
        // we are below the layer we were
        state.selected = currentHash
        self.mode = .selectionUpdated
      }
    case .selectionUpdated:
      ()
    }
  }
  mutating func beforeChild() -> Bool { false }
  mutating func afterChild(nextChildHash: Hash, index: Int, childCount: Int) -> Bool {
    switch mode {
    case .findingSelected:
      ()
    case .foundSelected:
      ()
    case .selectionUpdated:
      return true
    }
    return false
  }
  mutating func afterGroup(ourHash: Hash, _ group: [any Block]) {
    path.removeLast()
  }
  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    appendPath(siblings: 0)
    if atSelected {
      // we are at the bottom and selected
      mode = .selectionUpdated
    } else {
      if path.count > selectedDepth {
        switch mode {
        case .findingSelected:
          ()
        case .foundSelected:
          // first child hash
          state.selected = currentHash
          self.mode = .selectionUpdated
        case .selectionUpdated:
          ()
        }
      }
    }
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
