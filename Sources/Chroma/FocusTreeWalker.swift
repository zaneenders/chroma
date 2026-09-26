struct FocusTreeWalker {
  let root: FocusNode
  private(set) var path: [Int]
  /// The scroll entered by the last successful `stepIn`, for focus-memory lookup.
  private(set) var enteredScrollID: WidgetID?

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
    case .stepIn:
      return stepIn()
    case .stepOut:
      return stepOut()
    }
  }

  private mutating func move(along axis: FocusNode.Axis, direction: Int) -> Bool {
    guard let origin = root.node(at: path) else { return false }
    for depth in path.indices.reversed() {
      let ancestorPath = Array(path.prefix(depth))
      guard let ancestor = root.node(at: ancestorPath) else { return false }
      let childIndex = path[depth]
      guard ancestor.children.indices.contains(childIndex) else { return false }
      guard ancestor.axis == axis else { continue }

      // Skip decorative siblings without focusable content.
      var siblingIndex = childIndex + direction
      while ancestor.children.indices.contains(siblingIndex) {
        if let destination = nearestLeaf(in: ancestor.children[siblingIndex], to: origin.rect) {
          path = ancestorPath + [siblingIndex] + destination
          return true
        }
        siblingIndex += direction
      }
    }
    return false
  }

  private func nearestLeaf(in root: FocusNode, to origin: Rect) -> [Int]? {
    var bestPath: [Int]?
    var bestDistance = Float.infinity
    let originCenter = Point(x: origin.minX + origin.size.width / 2, y: origin.minY + origin.size.height / 2)

    func visit(_ node: FocusNode, path: [Int]) {
      if node.isLeaf {
        guard node.acceptsFocus else { return }
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

  private func center(of rect: Rect) -> Point {
    Point(x: rect.minX + rect.size.width / 2, y: rect.minY + rect.size.height / 2)
  }

  private func squaredDistance(_ a: Point, _ b: Point) -> Float {
    let x = a.x - b.x
    let y = a.y - b.y
    return x * x + y * y
  }
}

extension FocusTreeWalker {
  /// Leaves the nearest enclosing scroll container for the closest focusable control outside it.
  ///
  /// Candidates may only climb out: leaves inside scrolls unrelated to the exited one are
  /// skipped, so a step out never dives sideways into a different scroll container.
  mutating func stepOut() -> Bool {
    guard let origin = root.node(at: path) else { return false }
    guard let scrollPath = enclosingScopePath(of: path) else { return false }
    let originCenter = center(of: origin.rect)
    var bestPath: [Int]?
    var bestDistance = Float.infinity

    func visit(_ node: FocusNode, path current: [Int]) {
      if isPrefixed(scrollPath, of: current) { return }
      if node.scrollID != nil, !isPrefixed(current, of: scrollPath) {
        // Unrelated scroll container: every leaf below sits inside it, so the whole subtree is skipped.
        return
      }
      if node.isLeaf {
        guard node.acceptsFocus else { return }
        for depth in current.indices {
          let ancestorPath = Array(current.prefix(depth))
          guard let ancestor = root.node(at: ancestorPath), ancestor.scrollID != nil else { continue }
          // Only scroll containers that also enclose the exited scroll may be crossed on the way out.
          guard isPrefixed(ancestorPath, of: scrollPath) else { return }
        }
        let distance = squaredDistance(center(of: node.rect), originCenter)
        if distance < bestDistance {
          bestDistance = distance
          bestPath = current
        }
        return
      }
      for (index, child) in node.children.enumerated() {
        visit(child, path: current + [index])
      }
    }

    visit(root, path: [])
    guard let bestPath else { return false }
    path = bestPath
    return true
  }

  /// Enters the nearest scroll container that does not contain the current focus, landing on
  /// its first focusable leaf. The caller overlays the scroll container's remembered leaf when one exists.
  ///
  /// Scroll containers that contain the current focus are already entered and stay transparent so nested
  /// sibling scroll containers inside them remain reachable; non-containing scroll containers are atomic targets.
  mutating func stepIn() -> Bool {
    guard let origin = root.node(at: path) else { return false }
    let originCenter = center(of: origin.rect)
    var bestPath: [Int]?
    var bestScrollID: WidgetID?
    var bestDistance = Float.infinity

    func visit(_ node: FocusNode, path current: [Int]) {
      if let scrollID = node.scrollID, !isPrefixed(current, of: path) {
        if let leaf = node.firstLeafPath() {
          let distance = squaredDistance(center(of: node.rect), originCenter)
          if distance < bestDistance {
            bestDistance = distance
            bestPath = current + leaf
            bestScrollID = scrollID
          }
        }
        return
      }
      for (index, child) in node.children.enumerated() {
        visit(child, path: current + [index])
      }
    }

    visit(root, path: [])
    guard let bestPath, let bestScrollID else { return false }
    path = bestPath
    enteredScrollID = bestScrollID
    return true
  }

  private func isPrefixed(_ prefix: [Int], of path: [Int]) -> Bool {
    prefix.count <= path.count && Array(path.prefix(prefix.count)) == prefix
  }

  private func enclosingScopePath(of path: [Int]) -> [Int]? {
    for depth in path.indices.reversed() {
      let ancestorPath = Array(path.prefix(depth))
      if root.node(at: ancestorPath)?.scrollID != nil { return ancestorPath }
    }
    return nil
  }
}
