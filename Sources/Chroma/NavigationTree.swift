struct NavigationNode {
  enum Kind: Equatable {
    case group(WidgetID?)
    case leaf(WidgetID)
  }

  let kind: Kind
  let rect: Rect
  let visibleRect: Rect
  let name: String?
  let renderPath: [Int]
  var children: [NavigationNode]

  init(root: FocusNode, viewport: Rect) {
    kind = .group(nil)
    rect = viewport
    visibleRect = viewport
    name = "Window"
    renderPath = []
    children = Self.children(of: root, path: [])
  }

  private init(
    kind: Kind, rect: Rect, visibleRect: Rect, name: String? = nil, renderPath: [Int], children: [NavigationNode] = []
  ) {
    self.kind = kind
    self.rect = rect
    self.visibleRect = visibleRect
    self.name = name
    self.renderPath = renderPath
    self.children = children
  }

  private static func children(of node: FocusNode, path: [Int]) -> [NavigationNode] {
    node.children.enumerated().flatMap { index, child -> [NavigationNode] in
      let childPath = path + [index]
      guard child.acceptsFocus else { return [] }
      if let id = child.leafID {
        return [NavigationNode(kind: .leaf(id), rect: child.rect, visibleRect: child.hitRect, renderPath: childPath)]
      }
      let descendants = children(of: child, path: childPath)
      guard !descendants.isEmpty else { return [] }
      if case .group = child.kind, let id = child.navigationID {
        return [
          NavigationNode(
            kind: .group(id), rect: child.rect, visibleRect: child.hitRect, name: child.navigationName,
            renderPath: childPath, children: descendants)
        ]
      }
      return descendants
    }
  }

  var id: WidgetID? {
    switch kind {
    case .group(let id): id
    case .leaf(let id): id
    }
  }

  var isGroup: Bool {
    if case .group = kind { return true }
    return false
  }

  func path(to renderPath: [Int]) -> [Int]? {
    for (index, child) in children.enumerated() {
      if child.renderPath == renderPath { return [index] }
      if let subpath = child.path(to: renderPath) { return [index] + subpath }
    }
    return nil
  }

  func path(to id: WidgetID) -> [Int]? {
    for (index, child) in children.enumerated() {
      if child.id == id { return [index] }
      if let subpath = child.path(to: id) { return [index] + subpath }
    }
    return nil
  }

  func node(at path: [Int]) -> NavigationNode? {
    var node = self
    for index in path {
      guard node.children.indices.contains(index) else { return nil }
      node = node.children[index]
    }
    return node
  }
}
