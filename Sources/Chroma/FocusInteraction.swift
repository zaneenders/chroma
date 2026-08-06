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
      editingLeaf = id
      caretOffset = .max
    }
  }

  func moveCursor(to path: [Int]) {
    guard let tree else { return }
    if selection == nil { selection = [] }
    let commands = tree.macro(from: selection ?? [], to: path)
    for command in commands { apply(command) }
    if !commands.isEmpty { lastMacro = commands }
  }

  func apply(_ command: UICommand) {
    guard let tree, let selection else { return }
    switch command {
    case .activate:
      activatePending = true
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
    case .pageUp, .pageDown, .home, .end:
      return
    case .nextLeaf, .previousLeaf:
      cycleLeaf(forward: command == .nextLeaf)
    case .up, .down, .left, .right:
      flattenedMove(command)
    }
  }

  func directionDelta(_ command: UICommand, axis: FocusAxis) -> Int? {
    switch (axis, command) {
    case (.vertical, .up), (.horizontal, .left), (.none, .up), (.none, .left):
      return -1
    case (.vertical, .down), (.horizontal, .right), (.none, .down), (.none, .right):
      return 1
    default:
      return nil
    }
  }

  func flattenedMove(_ command: UICommand) {
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
