struct MoveUpWalker: L2ElementWalker {

  private let startingSelection: Hash
  private(set) var state: BlockState
  var currentHash: Hash = hash(contents: "0")
  // Protect against moving into layers below selected.
  // That is left to the move in and out commands
  private var selectedDepth = 0

  private var path: [SelectedPathNode] = []
  private var mode: Mode = .lookingForSelected

  enum Mode {
    case lookingForSelected
    case foundSelected
    case updatedSelected
  }

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
    path.removeLast()
  }
  mutating func beforeGroup(_ group: [L2Element]) {
    appendPath(siblings: group.count - 1)
  }

  mutating func walkGroup(_ group: [L2Element]) {
    let ourHash = currentHash
    beforeGroup(group)

    child_loop: for (index, element) in group.enumerated().reversed() {
      switch mode {
      case .foundSelected:
        ()
      case .lookingForSelected:
        ()
      case .updatedSelected:
        break child_loop
      }
      currentHash = hash(contents: "\(ourHash)\(#function)\(index)")
      switch element {
      case .group(let innerGroup):
        walkGroup(innerGroup)
      case let .text(txt, binding):
        walkText(txt, binding)
      }
      switch mode {
      case .foundSelected:
        switch path.last! {
        case let .layer(siblings: count):
          guard path.count < selectedDepth else {
            break child_loop
          }
          if count > 0 {  // has siblings
            guard index - 1 >= 0 else {
              break child_loop
            }
            state.selected = hash(contents: "\(ourHash)\(#function)\(index - 1)")
            mode = .updatedSelected
            break child_loop
          }
        case .selected:
          // we need to go back up a layer before doing anything.
          break child_loop
        }
      case .lookingForSelected:
        ()
      case .updatedSelected:
        break child_loop
      }
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
