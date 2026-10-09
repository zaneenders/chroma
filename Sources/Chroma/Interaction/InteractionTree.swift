public enum FocusGroupAxis: Equatable, Sendable {
  case horizontal
  case vertical
}

/// Committed interaction geometry outlives the operation-local layout buffer.
/// The render and navigation views link the same rows; neither owns node objects.
final class InteractionTree {
  struct Links {
    var parent = -1
    var first = -1
    var last = -1
    var previous = -1
    var next = -1
    var ordinal = 0
    var count = 0
  }

  struct Row {
    var kind: InteractionNode.Kind
    var rect: Rect
    var hitRect: Rect
    var scrollID: WidgetID?
    var navigationID: WidgetID?
    var navigationName: String?
    var canBeRevealed: Bool
    var navigationIgnored: Bool
    var render = Links()
    var navigation = Links()
  }

  var rows: [Row] = []
  private var leafIDs: Set<WidgetID> = []
  var generation = 0
  var viewport = Rect.zero

  var count: Int { rows.count }
  var capacity: Int { rows.capacity }
  var root: InteractionNode { node(0) }

  func reset() {
    generation += 1
    rows.removeAll(keepingCapacity: true)
    leafIDs.removeAll(keepingCapacity: true)
    _ = append(kind: .group, rect: .zero)
  }

  func clear() {
    generation += 1
    rows.removeAll(keepingCapacity: true)
    leafIDs.removeAll(keepingCapacity: true)
  }

  @discardableResult
  func append(
    kind: InteractionNode.Kind, rect: Rect, hitRect: Rect? = nil,
    parent: InteractionNode? = nil, scrollID: WidgetID? = nil,
    navigationID: WidgetID? = nil, navigationName: String? = nil,
    canBeRevealed: Bool = false, navigationIgnored: Bool = false
  ) -> InteractionNode {
    if case .leaf(let id) = kind {
      precondition(leafIDs.insert(id).inserted, "Duplicate interaction leaf ID: \(id)")
    }
    let index = rows.count
    rows.append(
      Row(
        kind: kind, rect: rect, hitRect: hitRect ?? rect,
        scrollID: scrollID, navigationID: navigationID, navigationName: navigationName,
        canBeRevealed: canBeRevealed, navigationIgnored: navigationIgnored))
    if let parent {
      parent.validate()
      precondition(parent.storage === self && parent.view == .render && parent.isGroup)
      link(index, to: parent.index, view: .render)
    }
    return node(index)
  }

  /// Only an unpublished builder tail may be pruned. beginGroup/endGroup never
  /// return its projection; the popped builder handle must be discarded here.
  /// Published rows stay intact until reset, which invalidates their generation.
  func removeEmptyGroup(_ node: InteractionNode) {
    node.validate()
    precondition(
      node.storage === self && node.view == .render && node.kind == .group
        && node.index == rows.count - 1 && node.children.isEmpty)
    let links = rows[node.index].render
    precondition(links.parent >= 0)
    rows[links.parent].render.last = links.previous
    rows[links.parent].render.count -= 1
    if links.previous >= 0 {
      rows[links.previous].render.next = -1
    } else {
      rows[links.parent].render.first = -1
    }
    rows.removeLast()
  }

  func node(_ index: Int, view: InteractionNode.View = .render) -> InteractionNode {
    InteractionNode(storage: self, index: index, view: view, generation: generation)
  }

  func links(_ index: Int, view: InteractionNode.View) -> Links {
    view == .render ? rows[index].render : rows[index].navigation
  }

  func link(_ child: Int, to parent: Int, view: InteractionNode.View) {
    let key: WritableKeyPath<Row, Links> = view == .render ? \.render : \.navigation
    let previous = rows[parent][keyPath: key].last
    rows[child][keyPath: key].parent = parent
    rows[child][keyPath: key].previous = previous
    rows[child][keyPath: key].ordinal = rows[parent][keyPath: key].count
    if previous >= 0 {
      rows[previous][keyPath: key].next = child
    } else {
      rows[parent][keyPath: key].first = child
    }
    rows[parent][keyPath: key].last = child
    rows[parent][keyPath: key].count += 1
  }
}

/// A borrowed indexed view. Invalid after its storage is reset; keep WidgetIDs
/// for persistent focus, never these projections or their row indices.
struct InteractionNode: Equatable {
  enum Kind: Equatable {
    case group
    case leaf(WidgetID)
  }
  enum View { case render, navigation }

  unowned let storage: InteractionTree
  let index: Int
  let view: View
  let generation: Int

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.storage === rhs.storage && lhs.index == rhs.index
      && lhs.view == rhs.view && lhs.generation == rhs.generation
  }

  func validate() {
    precondition(generation == storage.generation, "Interaction node used after storage reset")
    precondition(storage.rows.indices.contains(index), "Interaction row is no longer present")
  }

  private var row: InteractionTree.Row {
    validate()
    return storage.rows[index]
  }
  var links: InteractionTree.Links {
    validate()
    return storage.links(index, view: view)
  }

  var kind: Kind { row.kind }
  var rect: Rect {
    validate()
    return view == .navigation && index == 0 ? storage.viewport : row.rect
  }
  var hitRect: Rect { row.hitRect }
  var visibleRect: Rect {
    validate()
    return view == .navigation && index == 0 ? storage.viewport : row.hitRect
  }
  var scrollID: WidgetID? { row.scrollID }
  var canBeRevealed: Bool { row.canBeRevealed }
  var isLeaf: Bool { if case .leaf = kind { true } else { false } }
  var isGroup: Bool { !isLeaf }
  var acceptsFocus: Bool { !row.navigationIgnored && (hitRect != .zero || canBeRevealed) }
  var leafID: WidgetID? { if case .leaf(let id) = kind { id } else { nil } }
  var id: WidgetID? { leafID ?? row.navigationID }
  var name: String? { index == 0 ? "Window" : row.navigationName }
  var children: InteractionChildren { InteractionChildren(parent: self) }

  var renderPath: [Int] {
    validate()
    var path: [Int] = []
    var current = index
    while storage.rows[current].render.parent >= 0 {
      path.append(storage.rows[current].render.ordinal)
      current = storage.rows[current].render.parent
    }
    return path.reversed()
  }

  func node(at path: [Int]) -> InteractionNode? {
    var node = self
    for index in path {
      guard node.children.indices.contains(index) else { return nil }
      node = node.children[index]
    }
    return node
  }

  func hitTest(_ point: Point) -> [Int]? {
    var child = links.last
    while child >= 0 {
      let node = storage.node(child, view: view)
      if node.hitRect.contains(point) {
        if node.isLeaf { return [node.links.ordinal] }
        if let sub = node.hitTest(point) { return [node.links.ordinal] + sub }
      }
      child = node.links.previous
    }
    return nil
  }

  func firstLeafPath() -> [Int]? {
    for (index, child) in children.enumerated() {
      if child.isLeaf, child.acceptsFocus { return [index] }
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
}

/// Ordinals preserve the scoped command path API. Iteration follows links
/// directly, without materializing arrays of child projections.
struct InteractionChildren: BidirectionalCollection {
  let parent: InteractionNode
  var startIndex: Int { 0 }
  var endIndex: Int { parent.links.count }
  var count: Int { endIndex }
  var indices: Range<Int> { startIndex..<endIndex }
  func index(after i: Int) -> Int { i + 1 }
  func index(before i: Int) -> Int { i - 1 }

  subscript(position: Int) -> InteractionNode {
    precondition(indices.contains(position))
    let links = parent.links
    var index: Int
    if position < links.count / 2 {
      index = links.first
      for _ in 0..<position { index = parent.storage.links(index, view: parent.view).next }
    } else {
      index = links.last
      for _ in (position + 1)..<links.count { index = parent.storage.links(index, view: parent.view).previous }
    }
    return parent.storage.node(index, view: parent.view)
  }

  struct Iterator: IteratorProtocol {
    let parent: InteractionNode
    var nextIndex: Int
    mutating func next() -> InteractionNode? {
      parent.validate()
      guard nextIndex >= 0 else { return nil }
      let node = parent.storage.node(nextIndex, view: parent.view)
      nextIndex = node.links.next
      return node
    }
  }

  func makeIterator() -> Iterator { Iterator(parent: parent, nextIndex: parent.links.first) }

  func makeIterator(startingAt offset: Int) -> Iterator {
    precondition(offset >= 0 && offset <= endIndex)
    return Iterator(parent: parent, nextIndex: offset == endIndex ? -1 : self[offset].index)
  }

  func firstIndex(where predicate: (InteractionNode) throws -> Bool) rethrows -> Int? {
    for (index, child) in enumerated() where try predicate(child) { return index }
    return nil
  }
}
extension InteractionTree {
  /// Adds only links. Geometry, keys, clipping and names remain in their render rows.
  func navigationRoot(viewport: Rect) -> InteractionNode {
    self.viewport = viewport
    for index in rows.indices { rows[index].navigation = Links() }
    projectNavigation(from: 0, into: 0)
    return node(0, view: .navigation)
  }

  private func projectNavigation(from renderParent: Int, into navigationParent: Int) {
    var child = rows[renderParent].render.first
    while child >= 0 {
      let current = node(child)
      if current.acceptsFocus {
        if current.isLeaf {
          link(child, to: navigationParent, view: .navigation)
        } else if rows[child].navigationID != nil {
          projectNavigation(from: child, into: child)
          if rows[child].navigation.count > 0 {
            link(child, to: navigationParent, view: .navigation)
          }
        } else {
          projectNavigation(from: child, into: navigationParent)
        }
      }
      child = rows[child].render.next
    }
  }
}

extension InteractionNode {
  func path(to renderPath: [Int]) -> [Int]? {
    validate()
    guard let target = storage.root.node(at: renderPath), target.index != index else { return nil }
    var current = target.index
    var result: [Int] = []
    while current != index {
      let links = storage.links(current, view: view)
      guard links.parent >= 0 else { return nil }
      result.append(links.ordinal)
      current = links.parent
    }
    return result.reversed()
  }

  func path(to id: WidgetID) -> [Int]? {
    for (index, child) in children.enumerated() {
      if child.id == id { return [index] }
      if let subpath = child.path(to: id) { return [index] + subpath }
    }
    return nil
  }
}
