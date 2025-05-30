@MainActor
/// Encapsulates the sate of the system. Primarily the block tree structure
/// and information about which block is selected.
public struct ChromaController: ~Copyable {
  private let block: any Block
  private var state = BlockState()

  init(_ block: consuming some Block) {
    self.block = block
    var l2Parser = InitialWalk(state: state)
    // selection is nil to start.
    self.block.parseTree(action: false, &l2Parser)
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
    block.parseTree(action: true, &action)
    self.state = action.state
  }
}

// MARK: Movement
// TODO don't make BlockContainer public, abstract with a protocol.
extension ChromaController {

  public mutating func up() {
    _ChromaLog.debug("MoveUp")
    var move = MoveUpLeftWalker(state: state, move: .vertical)
    block.parseTree(action: false, &move)
    self.state = move.state
  }

  public mutating func left() {
    _ChromaLog.debug("MoveLeft")
    var move = MoveUpLeftWalker(state: state, move: .horizontal)
    block.parseTree(action: false, &move)
    self.state = move.state
  }

  public mutating func down() {
    _ChromaLog.debug("MoveDown")
    var move = MoveDownRightWalker(state: state, move: .vertical)
    block.parseTree(action: false, &move)
    self.state = move.state
  }

  public mutating func right() {
    _ChromaLog.debug("MoveRight")
    var move = MoveDownRightWalker(state: state, move: .horizontal)
    block.parseTree(action: false, &move)
    self.state = move.state
  }

  public mutating func `in`() {
    _ChromaLog.debug("MoveIn")
    var move = MoveInWalker(state: state)
    block.parseTree(action: false, &move)
    self.state = move.state
  }

  public mutating func out() {
    _ChromaLog.debug("MoveOut")
    var move = MoveOutWalker(state: state)
    block.parseTree(action: false, &move)
    self.state = move.state
  }
}
