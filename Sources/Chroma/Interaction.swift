public enum InteractionMode: Equatable, Sendable {
  case movement
  case editing
}

@MainActor
package final class Interaction {
  package let textSelection = TextSelectionManager()

  package var fontMetrics = FontMetrics()

  package private(set) var input = InputState()

  package var frameRate: Double = 0

  package internal(set) var selection: [Int]?

  package internal(set) var lastMacro: [Command] = []

  package var groupCursorColor = Color(r: 0.35, g: 0.6, b: 1, a: 0.4)

  var tree: FocusNode?

  var pressedLeaf: WidgetID?

  package internal(set) var editingLeaf: WidgetID?

  package internal(set) var caretOffset: Int = 0
  package internal(set) var textSelectionRange: Range<Int>?
  package internal(set) var editingText: String?

  public package(set) var mode: InteractionMode = .movement
  package var isTextEditing: Bool { mode == .editing }

  var activatePending = false
  private var redrawRequested = false
  var pendingCommands: [Command] = []
  var handledCommandIndices: Set<Int> = []
  struct ScopedCommandHandler {
    var path: [Int]
    var command: Command
    var action: @MainActor () -> CommandResult
  }
  var commandHandlers: [ScopedCommandHandler] = []
  var buildingCommandHandlers: [ScopedCommandHandler] = []
  var actionRoles: [ActionRole: @MainActor () -> Void] = [:]

  var lastPointerPosition = Point(x: -1, y: -1)

  package private(set) var dragOrigin: Point? = nil
  package private(set) var dragCurrent: Point = Point(x: -1, y: -1)
  package var isDragging: Bool { dragOrigin != nil && input.pointerDown }
  package var dragRect: Rect? {
    guard let origin = dragOrigin, isDragging else { return nil }
    return Rect(
      x: min(origin.x, dragCurrent.x),
      y: min(origin.y, dragCurrent.y),
      width: abs(dragCurrent.x - origin.x),
      height: abs(dragCurrent.y - origin.y))
  }

  package var onCopy: (() -> String?)?

  package func copyText() -> String? {
    if let text = onCopy?(), !text.isEmpty { return text }
    if isTextEditing, let range = textSelectionRange, let editingText {
      let characters = Array(editingText)
      guard range.lowerBound >= 0, range.upperBound <= characters.count else { return nil }
      return String(characters[range])
    }
    return textSelection.selectedText()
  }

  var scrollOffsets: [WidgetID: Float] = [:]
  var horizontalScrollOffsets: [WidgetID: Float] = [:]
  var scrollLimits: [WidgetID: Float] = [:]
  var horizontalScrollLimits: [WidgetID: Float] = [:]
  var scrollViewports: [Rect] = []
  var buildingScrollViewports: [Rect] = []

  var clipStack: [Rect] = []

  var selectedLeafID: WidgetID?

  var builderRoot: FocusNode?
  var builderStack: [FocusNode] = []
  var builderPath: [Int] = []

  package init() {}

  func beginEditing(_ id: WidgetID, caretOffset: Int) {
    editingLeaf = id
    self.caretOffset = caretOffset
    textSelectionRange = nil
    mode = .editing
  }

  func endEditing() {
    editingLeaf = nil
    editingText = nil
    textSelectionRange = nil
    mode = .movement
  }

  func requestRedraw() {
    redrawRequested = true
  }

  package func consumeRedrawRequest() -> Bool {
    defer { redrawRequested = false }
    return redrawRequested
  }

  package func beginFrame(input: InputState) {
    self.input = input
    activatePending = false
    pendingCommands = input.commands
    handledCommandIndices = []
    routePendingCommands()
    pendingCommands = []
    buildingCommandHandlers = []
    actionRoles = [:]

    let root = FocusNode(kind: .group(.vertical), rect: .zero)
    builderRoot = root
    builderStack = [root]
    builderPath = []
    clipStack = []
    buildingScrollViewports = []

    if input.pointerPressed {
      textSelection.clear()
    }
    textSelection.updateFromDrag(interaction: self)
    textSelection.layoutRegistry.clear()

    defer {
      selectedLeafID = selection.flatMap { tree?.node(at: $0)?.leafID }
      if let editingLeaf, editingLeaf != selectedLeafID {
        endEditing()
      }
      lastPointerPosition = input.pointerPosition
      if input.pointerPressed {
        dragOrigin = input.pointerPressPosition
      }
      if input.pointerReleased {
        dragOrigin = nil
      }
      if isDragging {
        dragCurrent = input.pointerPosition
      }
    }

    guard let tree else { return }

    let hovered = tree.hitTest(input.pointerPosition)
    if input.pointerPressed {
      if let hovered { moveCursor(to: hovered) }
      pressedLeaf = hovered.flatMap { tree.node(at: $0)?.leafID }
    } else if input.pointerPosition != lastPointerPosition, let hovered, hovered != selection {
      moveCursor(to: hovered)
    }
    if input.pointerReleased {
      if let pressedLeaf, let hovered, hovered == selection,
        tree.node(at: hovered)?.leafID == pressedLeaf
      {
        apply(.action(.activate))
      }
      self.pressedLeaf = nil
    }

    let wheelIsOverScrollView = scrollViewports.contains { $0.contains(input.pointerPosition) }
    if !wheelIsOverScrollView {
      if input.scrollDelta.y > 0 {
        apply(.navigation(.up))
      } else if input.scrollDelta.y < 0 {
        apply(.navigation(.down))
      }
    }

  }

  package func endFrame() {
    routePendingCommands()
    guard let newTree = builderRoot else { return }
    if let selection, let oldTree = tree {
      if let id = oldTree.node(at: selection)?.leafID {
        self.selection = newTree.findLeaf(id) ?? newTree.clamped(selection)
      } else {
        self.selection = newTree.clamped(selection)
      }
    }
    if selection == nil {
      selection = newTree.firstLeafPath()
    }
    if let editingLeaf, newTree.findLeaf(editingLeaf) == nil {
      endEditing()
    }
    tree = newTree
    commandHandlers = buildingCommandHandlers
    scrollViewports = buildingScrollViewports
    builderRoot = nil
    builderStack = []
    buildingScrollViewports = []
    activatePending = false
  }
}

@MainActor
extension Interaction {
  func beginGroup(_ axis: FocusAxis, rect: Rect) {
    guard let parent = builderStack.last else {
      preconditionFailure("beginGroup outside of a frame; call beginFrame first")
    }
    let node = FocusNode(kind: .group(axis), rect: rect)
    parent.children.append(node)
    builderPath.append(parent.children.count - 1)
    builderStack.append(node)
  }

  /// Finishes the current group and reports whether it was retained in the focus tree.
  /// Empty groups are pruned, so callers must not render a focus cursor for them: a
  /// later sibling can reuse the same path during this frame.
  @discardableResult
  func endGroup() -> Bool {
    guard builderStack.count > 1, let node = builderStack.popLast() else {
      preconditionFailure("endGroup without a matching beginGroup")
    }
    builderPath.removeLast()
    if node.children.isEmpty {
      builderStack.last?.children.removeLast()
      return false
    }
    return true
  }

  var isCurrentGroupSelected: Bool {
    guard let selection, selectedLeafID == nil else { return false }
    return selection == builderPath
  }

  func focus(_ id: WidgetID, editing: Bool = false) {
    guard let tree, let path = tree.findLeaf(id) else { return }
    moveCursor(to: path)
    if editing {
      beginEditing(id, caretOffset: .max)
    }
  }

  func moveCursor(to path: [Int]) {
    guard let tree else { return }
    if selection == nil { selection = [] }
    let commands = tree.macro(from: selection ?? [], to: path)
    for command in commands { apply(command) }
    if !commands.isEmpty { lastMacro = commands }
  }

  private func isPrefix(_ prefix: [Int], of path: [Int]) -> Bool {
    prefix.count <= path.count && Array(path.prefix(prefix.count)) == prefix
  }

  func routePendingCommands() {
    for (index, command) in pendingCommands.enumerated() where !handledCommandIndices.contains(index) {
      let handlers =
        commandHandlers
        .filter { $0.command == command && isPrefix($0.path, of: selection ?? []) }
        .sorted { $0.path.count > $1.path.count }
      if handlers.contains(where: { $0.action() == .handled }) { continue }
      switch command {
      case .action(.submit):
        actionRoles[.defaultAction]?()
      case .action(.cancel), .action(.dismiss):
        actionRoles[.cancel]?()
      default:
        apply(command)
      }
    }
  }

  func apply(_ command: Command) {
    guard let tree, let selection else { return }
    switch command {
    case .application, .editing:
      return
    case .action(.activate):
      activatePending = true
    case .action(.submit), .action(.cancel), .action(.dismiss):
      return
    case .navigation(let navigation):
      apply(navigation, tree: tree, selection: selection)
    }
  }

  private func apply(_ command: NavigationCommand, tree: FocusNode, selection: [Int]) {
    switch command {
    case .in:
      if let node = tree.node(at: selection), !node.children.isEmpty {
        self.selection = selection + [0]
      } else {
        activatePending = true
      }
    case .out:
      if !selection.isEmpty {
        self.selection = Array(selection.dropLast())
      }
    case .pageUp, .pageDown:
      return
    case .home:
      self.selection = tree.firstLeafPath()
    case .end:
      self.selection = tree.lastLeafPath()
    case .next, .previous:
      cycleLeaf(forward: command == .next)
    case .up, .down, .left, .right:
      flattenedMove(command)
    }
  }

  func directionDelta(_ command: NavigationCommand, axis: FocusAxis) -> Int? {
    switch (axis, command) {
    case (.vertical, .up), (.horizontal, .left), (.none, .up), (.none, .left):
      return -1
    case (.vertical, .down), (.horizontal, .right), (.none, .down), (.none, .right):
      return 1
    default:
      return nil
    }
  }

  func flattenedMove(_ command: NavigationCommand) {
    guard let tree, let selection else { return }
    let forward = command == .down || command == .right

    var level = selection.count - 1
    while level >= 0 {
      let parentPath = Array(selection.prefix(level))
      guard let parent = tree.node(at: parentPath), let axis = parent.axis else { break }
      if let delta = directionDelta(command, axis: axis) {
        let next = selection[level] + delta
        if next >= 0, next < parent.children.count {
          var newPath = parentPath + [next]
          if level < selection.count - 1 {
            while let node = tree.node(at: newPath), !node.isLeaf, !node.children.isEmpty {
              newPath.append(forward ? 0 : node.children.count - 1)
            }
          }
          self.selection = newPath
          return
        }
      }
      level -= 1
    }

    perpendicularMove(command)
  }

  /// Crosses the nearest perpendicular group after ordinary axis-aware bubbling
  /// has failed. This makes adjacent panes navigable while preserving row/column
  /// movement semantics.
  func perpendicularMove(_ command: NavigationCommand) {
    guard let tree, let selection else { return }
    var level = selection.count - 1
    while level >= 0 {
      let parentPath = Array(selection.prefix(level))
      guard let parent = tree.node(at: parentPath), let axis = parent.axis else { break }
      guard directionDelta(command, axis: axis) == nil, parent.children.count > 1 else {
        level -= 1
        continue
      }
      let delta = command == .right || command == .down ? 1 : -1
      let next = selection[level] + delta
      if next >= 0, next < parent.children.count {
        var newPath = parentPath + [next]
        while let node = tree.node(at: newPath), !node.isLeaf, !node.children.isEmpty {
          newPath.append(delta > 0 ? 0 : node.children.count - 1)
        }
        self.selection = newPath
        return
      }
      level -= 1
    }
  }

  func cycleLeaf(forward: Bool) {
    guard let tree, let selection else { return }
    let leaves = tree.leafPaths()
    guard let first = leaves.first, let last = leaves.last else { return }
    if forward {
      self.selection = leaves.first(where: { selection.lexicographicallyPrecedes($0) }) ?? first
    } else {
      self.selection = leaves.last(where: { $0.lexicographicallyPrecedes(selection) }) ?? last
    }
  }
}

@MainActor
extension Interaction {
  func pushClip(_ rect: Rect) {
    let clip = clipStack.last.flatMap { $0.intersection(rect) } ?? (clipStack.isEmpty ? rect : .zero)
    clipStack.append(clip)
  }

  func popClip() {
    guard !clipStack.isEmpty else {
      preconditionFailure("popClip without a matching pushClip")
    }
    clipStack.removeLast()
  }

  func interactiveBehavior(
    id: WidgetID, rect: Rect, role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    guard let parent = builderStack.last else {
      preconditionFailure("interactiveBehavior outside of a frame; call beginFrame first")
    }
    parent.children.append(FocusNode(kind: .leaf(id), rect: clippedRect(rect), role: role))
    if role != .normal, let action { actionRoles[role] = action }

    let selected = selectedLeafID == id
    let held = pressedLeaf == id && input.pointerDown
    var clicked = false
    if selected && activatePending {
      clicked = true
      activatePending = false
      requestRedraw()
    }
    return ButtonState(hovered: selected, held: held, clicked: clicked)
  }

  func clippedRect(_ rect: Rect) -> Rect {
    guard let clip = clipStack.last else { return rect }
    return rect.intersection(clip) ?? .zero
  }

}

@MainActor
extension Interaction {
  package var selectionDescription: String {
    guard let selection else { return "—" }
    let path = selection.isEmpty ? "·" : selection.map(String.init).joined(separator: ".")
    let kind = selectedLeafID != nil ? "leaf" : selection.isEmpty ? "root" : "group"
    return "\(path) (\(kind))"
  }

  package var lastMacroDescription: String {
    lastMacro.isEmpty ? "—" : lastMacro.map(\.label).joined(separator: " ")
  }

}
