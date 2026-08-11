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

  func apply(_ command: UICommand) {
    apply(command.command)
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
    case .home, .first:
      self.selection = tree.firstLeafPath()
    case .end, .last:
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
