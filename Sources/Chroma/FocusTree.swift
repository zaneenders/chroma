/// The orientation of a focus group: the axis sibling movement runs along.
public enum FocusAxis: Equatable, Sendable {
  /// Children are laid out side by side; `left` / `right` move between them.
  case horizontal
  /// Children are laid out top to bottom; `up` / `down` move between them.
  case vertical
  /// Overlapping children (`ZStack`): every direction cycles through
  /// siblings, since overlapping widgets have no spatial direction.
  case none
}

/// One node in the focus tree: either a group begun by a stack while drawing
/// or a leaf registered by an interactive widget.
///
/// The tree is rebuilt from scratch every frame as blocks draw; navigation
/// commands always run against the previous frame's tree, one frame behind —
/// the same trade the rest of the immediate-mode interaction state makes.
/// Positions in the tree are addressed by path: the list of child indices
/// from the root (`[]` is the root itself).
final class FocusNode {
  enum Kind: Equatable {
    case group(FocusAxis)
    case leaf(WidgetID)
  }

  let kind: Kind
  /// The rect the stack or widget was assigned last frame, in pixel space.
  let rect: Rect
  var children: [FocusNode] = []

  init(kind: Kind, rect: Rect) {
    self.kind = kind
    self.rect = rect
  }

  var isLeaf: Bool {
    guard case .leaf = kind else { return false }
    return true
  }

  /// The widget identity of a leaf node; nil for groups.
  var leafID: WidgetID? {
    guard case .leaf(let id) = kind else { return nil }
    return id
  }

  /// The movement axis of a group node; nil for leaves.
  var axis: FocusAxis? {
    guard case .group(let axis) = kind else { return nil }
    return axis
  }
}

extension FocusNode {
  /// The node at `path`, or nil if any index along it is out of range.
  func node(at path: [Int]) -> FocusNode? {
    var node = self
    for index in path {
      guard index >= 0, index < node.children.count else { return nil }
      node = node.children[index]
    }
    return node
  }

  /// The path of the deepest leaf containing `point`, searching last-drawn
  /// (top-most) children first so overlapping widgets hit-test like they
  /// paint. A point inside a group but over none of its leaves falls through
  /// to siblings drawn underneath; nothing hovered returns nil.
  func hitTest(_ point: Point) -> [Int]? {
    for (index, child) in children.enumerated().reversed() {
      guard child.rect.contains(point) else { continue }
      if child.isLeaf { return [index] }
      if let sub = child.hitTest(point) { return [index] + sub }
    }
    return nil
  }

  /// The path of the first leaf in depth-first order: the cursor's starting
  /// position when nothing has been selected yet.
  func firstLeafPath() -> [Int]? {
    for (index, child) in children.enumerated() {
      if child.isLeaf { return [index] }
      if let sub = child.firstLeafPath() { return [index] + sub }
    }
    return nil
  }

  /// The path of the leaf with `id`, depth-first. Used to re-attach the
  /// cursor to the same widget after the tree is rebuilt, wherever it moved.
  func findLeaf(_ id: WidgetID) -> [Int]? {
    for (index, child) in children.enumerated() {
      if child.leafID == id { return [index] }
      if let sub = child.findLeaf(id) { return [index] + sub }
    }
    return nil
  }

  /// `path` walked as far as possible in this tree, clamping each index into
  /// range. Keeps a group cursor somewhere sane when the tree's shape
  /// changes between frames.
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

  /// The command sequence walking the cursor `from` one node `to` another:
  /// `out` to the lowest common ancestor, then `in` plus sibling moves back
  /// down to the target.
  ///
  /// This is the mouse macro: hovering a leaf compiles into exactly the
  /// moves that would have walked the keyboard cursor there, so pointer and
  /// keyboard share one code path and one cursor.
  func macro(from: [Int], to: [Int]) -> [UICommand] {
    var common = 0
    while common < min(from.count, to.count) && from[common] == to[common] {
      common += 1
    }
    var commands = [UICommand](repeating: .out, count: from.count - common)
    for level in common..<to.count {
      commands.append(.in)
      // `in` always lands on the first child, so only forward moves remain.
      // Axis-less (overlapping) groups accept any direction; use `down`.
      let forward: UICommand = node(at: Array(to.prefix(level)))?.axis == .horizontal ? .right : .down
      commands.append(contentsOf: [UICommand](repeating: forward, count: to[level]))
    }
    return commands
  }
}
