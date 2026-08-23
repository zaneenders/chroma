public enum FocusAxis: Equatable, Sendable {
  case horizontal
  case vertical
  case none
}

final class FocusNode {
  enum Kind: Equatable {
    case group(FocusAxis)
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

  var axis: FocusAxis? {
    guard case .group(let axis) = kind else { return nil }
    return axis
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

  func lastLeafPath() -> [Int]? {
    for (index, child) in children.enumerated().reversed() {
      if child.isLeaf { return [index] }
      if let sub = child.lastLeafPath() { return [index] + sub }
    }
    return nil
  }

  func leafPaths() -> [[Int]] {
    var result: [[Int]] = []
    for (index, child) in children.enumerated() {
      if child.isLeaf {
        result.append([index])
      } else {
        result.append(contentsOf: child.leafPaths().map { [index] + $0 })
      }
    }
    return result
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

  func macro(from: [Int], to: [Int]) -> [Command] {
    var common = 0
    while common < min(from.count, to.count) && from[common] == to[common] {
      common += 1
    }
    var commands = [Command](repeating: .navigation(.out), count: from.count - common)
    for level in common..<to.count {
      commands.append(.navigation(.in))
      let forward: Command =
        node(at: Array(to.prefix(level)))?.axis == .horizontal
        ? .navigation(.right) : .navigation(.down)
      commands.append(contentsOf: [Command](repeating: forward, count: to[level]))
    }
    return commands
  }
}
