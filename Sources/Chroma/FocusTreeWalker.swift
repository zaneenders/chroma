struct FocusTreeWalker {
  let root: FocusNode
  private(set) var path: [Int]

  init?(root: FocusNode, path: [Int]) {
    guard root.node(at: path) != nil else { return nil }
    self.root = root
    self.path = path
  }

  mutating func move(_ command: NavigationCommand) -> Bool {
    switch command {
    case .up:
      return move(along: .vertical, direction: -1)
    case .down:
      return move(along: .vertical, direction: 1)
    case .left:
      return move(along: .horizontal, direction: -1)
    case .right:
      return move(along: .horizontal, direction: 1)
    case .inward:
      return moveInward()
    case .outward:
      return moveOutward()
    }
  }

  private mutating func move(along axis: FocusNode.Axis, direction: Int) -> Bool {
    var ancestor = root
    for depth in path.indices {
      let childIndex = path[depth]
      guard ancestor.children.indices.contains(childIndex) else { return false }
      if ancestor.axis == axis {
        let siblingIndex = childIndex + direction
        if ancestor.children.indices.contains(siblingIndex) {
          path[depth] = siblingIndex
          replayDescendantPath(in: ancestor.children[siblingIndex], after: depth, direction: direction)
          skipTransparentGroups()
          return true
        }
      }
      ancestor = ancestor.children[childIndex]
    }
    return false
  }

  private mutating func replayDescendantPath(
    in destination: FocusNode, after depth: Int, direction: Int
  ) {
    var node = destination
    var index = depth + 1
    while index < path.count, !node.children.isEmpty {
      let desiredIndex = path[index]
      let destinationIndex: Int
      if node.children.indices.contains(desiredIndex) {
        destinationIndex = desiredIndex
      } else {
        destinationIndex =
          direction > 0 ? node.children.startIndex : node.children.index(before: node.children.endIndex)
      }
      path[index] = destinationIndex
      node = node.children[destinationIndex]
      index += 1
    }
    path.removeLast(path.count - index)
  }

  private mutating func moveInward() -> Bool {
    guard let node = root.node(at: path), !node.isLeaf, !node.children.isEmpty else { return false }
    path.append(node.children.startIndex)
    return true
  }

  private mutating func skipTransparentGroups() {
    while let node = root.node(at: path), !node.isLeaf, node.axis == nil, node.children.count == 1 {
      path.append(node.children.startIndex)
    }
  }

  private mutating func moveOutward() -> Bool {
    guard !path.isEmpty else { return false }
    path.removeLast()
    return true
  }
}
