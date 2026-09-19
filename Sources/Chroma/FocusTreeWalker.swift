struct FocusTreeWalker {
  let root: FocusNode
  private(set) var path: [Int]

  init?(root: FocusNode, path: [Int]) {
    guard root.node(at: path)?.isLeaf == true else { return nil }
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
    }
  }

  private mutating func move(along axis: FocusNode.Axis, direction: Int) -> Bool {
    guard let origin = root.node(at: path) else { return false }
    var ancestor = root
    for depth in path.indices {
      let childIndex = path[depth]
      guard ancestor.children.indices.contains(childIndex) else { return false }
      if ancestor.axis == axis {
        let siblingIndex = childIndex + direction
        if ancestor.children.indices.contains(siblingIndex),
          let destination = nearestLeaf(in: ancestor.children[siblingIndex], to: origin.rect)
        {
          path.removeLast(path.count - depth)
          path.append(siblingIndex)
          path.append(contentsOf: destination)
          return true
        }
      }
      ancestor = ancestor.children[childIndex]
    }
    return false
  }

  private func nearestLeaf(in root: FocusNode, to origin: Rect) -> [Int]? {
    var bestPath: [Int]?
    var bestDistance = Float.infinity
    let originCenter = Point(x: origin.minX + origin.size.width / 2, y: origin.minY + origin.size.height / 2)

    func visit(_ node: FocusNode, path: [Int]) {
      if node.isLeaf {
        let center = Point(x: node.rect.minX + node.rect.size.width / 2, y: node.rect.minY + node.rect.size.height / 2)
        let x = center.x - originCenter.x
        let y = center.y - originCenter.y
        let distance = x * x + y * y
        if distance < bestDistance {
          bestDistance = distance
          bestPath = path
        }
        return
      }
      for (index, child) in node.children.enumerated() {
        visit(child, path: path + [index])
      }
    }

    visit(root, path: [])
    return bestPath
  }
}
