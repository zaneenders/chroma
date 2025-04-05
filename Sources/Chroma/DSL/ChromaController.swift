@MainActor
/// Encapsulates the sate of the system. Primarily the block tree structure
/// and information about which block is selected.
public struct ChromaController: ~Copyable {
  private let block: any Block
  private var state = BlockState()

  init(_ block: consuming some Block) {
    self.block = block
    var l2Parser = InitialWalk(state: state)
    let l2Tree = self.block.parseTree(action: false, selected: "")

    l2Parser.walk(l2Tree)
    self.state = l2Parser.state
  }

  /// This is called
  /// - Parameter renderer: The renderer to draw the current state of the system with.
  func observe<R: Renderer>(with renderer: inout R) where R: ~Copyable {
    renderer.view(block, with: state)
  }

  /// Called to trigger a `.bind` function or a movement action.
  /// - Parameter code: the input received from the user.
  mutating func action(_ code: AsciiKeyCode) {
    var action = ActionWalker(state: state, input: code)
    let l2Tree = block.parseTree(action: true, selected: "")
    action.walk(l2Tree)
    self.state = action.state
  }
}

// MARK: Movement
// TODO don't make BlockContainer public, abstract with a protocol.
extension ChromaController {

  public mutating func up() {
    Log.debug("MoveUp")
    var move = MoveUpWalker(state: state)
    let l2Tree = block.parseTree(action: true, selected: "")
    move.walk(l2Tree)
    self.state = move.state
  }

  public mutating func down() {
    Log.debug("MoveDown")
    var move = MoveDownWalker(state: state)
    let l2Tree = block.parseTree(action: true, selected: "")
    move.walk(l2Tree)
    self.state = move.state
  }

  public mutating func `in`() {
    Log.debug("MoveIn")
    var move = MoveInWalker(state: state)
    let l2Tree = block.parseTree(action: true, selected: "")
    move.walk(l2Tree)
    self.state = move.state
  }

  public mutating func out() {
    Log.debug("MoveOut")
    var move = MoveOutWalker(state: state)
    let l2Tree = block.parseTree(action: true, selected: "")
    move.walk(l2Tree)
    self.state = move.state
  }
}
