enum SelectedPathNode {
  case selected
  case layer(siblings: Int)
}

struct MoveDownRightWalker: ElementWalker {
  private let startingSelection: Hash
  private(set) var state: BlockState
  var currentHash: Hash = hash(contents: "0")
  private var path: [SelectedPathNode] = []
  private var mode: Mode = .lookingForSelected
  // Protect against moving into layers below selected.
  // That is left to the move in and out commands
  private var selectedDepth = 0
  var orientation: Orientation
  let move: Orientation

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
      guard path.count < selectedDepth else {
        return true
      }
      switch path.last! {
      case let .layer(siblings: count):
        if count > 0 {  // has siblings
          guard index + 1 < childCount else {
            return true
          }
          // state.selected = hash(contents: "\(ourHash)\(#function)\(index + 1)")
          state.selected = nextChildHash
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

  mutating func afterGroup(ourHash: Hash) {
    path.removeLast()
  }

  mutating func walkText(_ text: String, _ binding: InputHandler?) {
    appendPath(siblings: 0)
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
