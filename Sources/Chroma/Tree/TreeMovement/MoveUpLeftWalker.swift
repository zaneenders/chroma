struct MoveUpLeftWalker: ElementWalker {

  private let startingSelection: Hash
  private(set) var state: BlockState
  var orientation: Orientation
  var currentHash: Hash = hash(contents: "0")
  // Protect against moving into layers below selected.
  // That is left to the move in and out commands
  private var selectedDepth = 0

  private var path: [SelectedPathNode] = []
  private var mode: Mode = .lookingForSelected
  private let move: Orientation

  enum Mode {
    case lookingForSelected
    case foundSelected
    case updatedSelected
  }

  init(state: BlockState, move: Orientation) {
    self.state = state
    self.startingSelection = state.selected!
    _ChromaLog.debug("\(self.startingSelection)")
    self.orientation = .vertical
    self.move = move
  }

  mutating func beforeGroup(childrenCount: Int) {
    appendPath(siblings: childrenCount - 1)
  }
  mutating func afterGroup(ourHash: Hash) {}
  mutating func beforeChild() -> Bool {
    switch mode {
    case .foundSelected:
      ()
    case .lookingForSelected:
      ()
    case .updatedSelected:
      return true
    }
    return false
  }
  mutating func afterChild(nextChildHash: Hash, prevChildHash: Hash, index: Int, childCount: Int) -> Bool {
    switch mode {
    case .foundSelected:
      guard orientation == move else {
        return true  // Should this be true or false?
      }
      switch path.last! {
      case let .layer(siblings: count):
        guard path.count < selectedDepth else {
          return true
        }
        if count > 0 {  // has siblings
          guard index - 1 >= 0 else {
            return true
          }
          // state.selected = hash(contents: "\(ourHash)\(#function)\(index - 1)")
          state.selected = prevChildHash
          mode = .updatedSelected
          return true
        }
      case .selected:
        // we need to go back up a layer before doing anything.
        return true
      }
    case .lookingForSelected:
      ()
    case .updatedSelected:
      return true
    }
    return false
  }
  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    appendPath(siblings: 0)
    path.removeLast()
  }

  mutating func afterGroup(ourHash: Hash, _ group: [any Block]) {
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
