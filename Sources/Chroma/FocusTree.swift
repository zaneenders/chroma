public enum FocusGroupAxis: Equatable, Sendable {
  case horizontal
  case vertical
}

final class FocusNode {
  typealias Axis = FocusGroupAxis

  enum Kind: Equatable {
    case group
    case leaf(WidgetID)
  }

  let kind: Kind
  let rect: Rect
  var role: ActionRole = .normal
  let axis: Axis?
  var commandHandlers: [Command: @MainActor () -> CommandResult] = [:]
  var children: [FocusNode] = []

  init(kind: Kind, rect: Rect, role: ActionRole = .normal, axis: Axis? = nil) {
    self.kind = kind
    self.rect = rect
    self.role = role
    self.axis = axis
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
      guard node.children.indices.contains(index) else { return nil }
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
      if let subpath = child.firstLeafPath() { return [index] + subpath }
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
