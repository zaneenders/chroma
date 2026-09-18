final class FocusNode {
  enum Kind: Equatable {
    case group
    case leaf(WidgetID)
  }

  let kind: Kind
  let rect: Rect
  var role: ActionRole = .normal
  var commandHandlers: [Command: @MainActor () -> CommandResult] = [:]
  var children: [FocusNode] = []

  init(kind: Kind, rect: Rect, role: ActionRole = .normal) {
    self.kind = kind
    self.rect = rect
    self.role = role
  }

  var isLeaf: Bool {
    guard case .leaf = kind else { return false }
    return true
  }

  var leafID: WidgetID? {
    guard case .leaf(let id) = kind else { return nil }
    return id
  }
}

extension FocusNode {
  func node(at path: [Int]) -> FocusNode? {
    var node = self
    for index in path {
      guard index >= 0, index < node.children.count else { return nil }
      node = node.children[index]
    }
    return node
  }

  func hitTest(_ point: Point) -> [Int]? {
    for (index, child) in children.enumerated().reversed() {
      guard child.rect.contains(point) else { continue }
      if child.isLeaf { return [index] }
      if let sub = child.hitTest(point) { return [index] + sub }
    }
    return nil
  }

  func firstLeafPath() -> [Int]? {
    for (index, child) in children.enumerated() {
      if child.isLeaf { return [index] }
      if let sub = child.firstLeafPath() { return [index] + sub }
    }
    return nil
  }

  func findLeaf(_ id: WidgetID) -> [Int]? {
    for (index, child) in children.enumerated() {
      if child.leafID == id { return [index] }
      if let sub = child.findLeaf(id) { return [index] + sub }
    }
    return nil
  }

  func clamped(_ path: [Int]) -> [Int] {
    var node = self
    var result: [Int] = []
    for index in path {
      guard !node.children.isEmpty else { break }
      let clamped = min(max(index, 0), node.children.count - 1)
      result.append(clamped)
      node = node.children[clamped]
    }
    return result
  }
}
