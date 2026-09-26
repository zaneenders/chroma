@MainActor
extension Interaction {
  func reconcileNavigation(in tree: FocusNode) {
    let next = NavigationNode(root: tree, viewport: viewport)
    let previous = navigation
    let previousSelection = navigationPath
    let previousLeafID = previous?.node(at: previousSelection)?.id
    navigation = next
    guard next.containsNavigationBoundaries else {
      navigationPath = []
      return
    }
    guard let previous else {
      navigationPath = []
      selection = nil
      selectedLeafID = nil
      return
    }

    if previousSelection.isEmpty {
      navigationPath = []
      selection = nil
      selectedLeafID = nil
      return
    }

    if let id = previous.node(at: previousSelection)?.id,
      let stablePath = next.path(to: id)
    {
      navigationPath = stablePath
    } else {
      var parentPath = Array(previousSelection.dropLast())
      while !parentPath.isEmpty {
        if let id = previous.node(at: parentPath)?.id, let survivingPath = next.path(to: id) {
          let children = next.node(at: survivingPath)?.children ?? []
          navigationPath =
            children.isEmpty
            ? survivingPath : survivingPath + [min(previousSelection[parentPath.count], children.count - 1)]
          synchronizeKeyboardSelection(in: tree, previousLeafID: previousLeafID)
          return
        }
        parentPath.removeLast()
      }
      navigationPath = next.children.isEmpty ? [] : [min(previousSelection[0], next.children.count - 1)]
    }

    synchronizeKeyboardSelection(in: tree, previousLeafID: previousLeafID)
  }

  private func synchronizeKeyboardSelection(in tree: FocusNode, previousLeafID: WidgetID?) {
    guard let selected = navigation?.node(at: navigationPath), case .leaf(let selectedID) = selected.kind else {
      selection = nil
      selectedLeafID = nil
      if editingLeaf != nil { endEditing() }
      return
    }

    if let path = tree.findLeaf(selectedID), tree.node(at: path)?.acceptsFocus == true {
      selection = path
      selectedLeafID = selectedID
      if previousLeafID != selectedID { reveal(path, in: tree) }
    } else {
      selection = nil
      selectedLeafID = nil
    }
  }

  func rememberNavigation(_ path: [Int], in root: NavigationNode) {
    guard !path.isEmpty else { return }
    for depth in 0..<path.count {
      let parent = root.node(at: Array(path.prefix(depth)))
      let child = root.node(at: Array(path.prefix(depth + 1)))
      if let groupID = parent?.id, let childID = child?.id {
        rememberedNavigation[groupID] = childID
      }
    }
  }

  private func setNavigationSelection(_ path: [Int]) {
    guard let navigation, let node = navigation.node(at: path) else { return }
    navigationPath = path
    rememberNavigation(path, in: navigation)
    if case .leaf(let leafID) = node.kind {
      guard let tree, let renderPath = tree.findLeaf(leafID),
        tree.node(at: renderPath)?.acceptsFocus == true
      else {
        selection = nil
        selectedLeafID = nil
        return
      }
      selection = renderPath
      selectedLeafID = leafID
      pendingFocus = nil
      recordFocusMemory(for: renderPath, in: tree)
      reveal(renderPath, in: tree)
    } else {
      selection = nil
      selectedLeafID = nil
      pendingFocus = nil
      endEditing()
      if let tree { reveal(node.renderPath, in: tree) }
    }
  }

  func selectNavigation(_ path: [Int]) {
    setNavigationSelection(path)
  }

  func selectNavigationLeaf(_ id: WidgetID) {
    guard let navigation, let path = navigation.path(to: id),
      navigation.node(at: path)?.isGroup == false
    else { return }
    setNavigationSelection(path)
  }

  func paintNavigation(into drawList: inout DrawList, theme: ChromaTheme) {
    guard let navigation, navigation.containsNavigationBoundaries else { return }
    let activePath = Array(navigationPath.dropLast())
    guard let activeGroup = navigation.node(at: activePath) else { return }
    drawList.strokeRoundedRect(activeGroup.visibleRect, radius: 5, width: 1, color: theme.border)
    guard !navigationPath.isEmpty, let selected = navigation.node(at: navigationPath) else { return }
    if selected.visibleRect != .zero {
      drawList.strokeRoundedRect(selected.visibleRect, radius: 5, width: 2, color: theme.focus.ring)
    }
  }

  func moveNavigation(_ command: NavigationCommand) {
    guard let navigation else { return }
    let activePath = Array(navigationPath.dropLast())
    guard let activeGroup = navigation.node(at: activePath) else { return }

    switch command {
    case .stepOut:
      guard !navigationPath.isEmpty, !activePath.isEmpty else { return }
      setNavigationSelection(activePath)
    case .stepIn:
      guard !navigationPath.isEmpty,
        let selected = navigation.node(at: navigationPath)
      else { return }
      guard selected.isGroup else {
        activatePending = true
        return
      }
      let rememberedID = selected.id.flatMap { rememberedNavigation[$0] }
      if let rememberedID, let childIndex = selected.children.firstIndex(where: { $0.id == rememberedID }) {
        setNavigationSelection(navigationPath + [childIndex])
      } else if let groupID = selected.id, let rememberedID,
        let rowKey = scrollRowKeys[groupID]?[rememberedID],
        scrollLayouts[groupID]?.rowKeys.contains(rowKey) == true,
        let contentRect = scrollRows[groupID]?[rememberedID]
      {
        let offset = scrollOffset(for: groupID)
        pendingScrollReveals[groupID] = Rect(
          x: contentRect.minX, y: contentRect.minY - offset,
          width: contentRect.size.width, height: contentRect.size.height)
        pendingFocus = PendingFocus(leaf: rememberedID, scrollID: groupID)
      } else if !selected.children.isEmpty {
        setNavigationSelection(navigationPath + [0])
      }
    case .left, .right, .up, .down:
      if navigationPath.isEmpty, !activeGroup.children.isEmpty {
        setNavigationSelection([0])
        return
      }
      var path = navigationPath
      while !path.isEmpty {
        let parentPath = Array(path.dropLast())
        if let parent = navigation.node(at: parentPath),
          let target = directionalNeighbor(command, currentPath: path, activeGroup: parent, navigation: navigation)
        {
          setNavigationSelection(target)
          return
        }
        path = parentPath
      }
    }
  }

  private func directionalNeighbor(
    _ command: NavigationCommand, currentPath: [Int], activeGroup: NavigationNode,
    navigation: NavigationNode
  ) -> [Int]? {
    guard !activeGroup.children.isEmpty, let current = navigation.node(at: currentPath) else {
      return nil
    }
    let direction: Int
    let primaryAxis: FocusNode.Axis
    switch command {
    case .left:
      direction = -1
      primaryAxis = .horizontal
    case .right:
      direction = 1
      primaryAxis = .horizontal
    case .up:
      direction = -1
      primaryAxis = .vertical
    case .down:
      direction = 1
      primaryAxis = .vertical
    case .stepIn, .stepOut: return nil
    }

    let currentPrefix = Array(currentPath.dropLast())
    let originCenter = center(of: current.rect)
    guard let currentIndex = currentPath.last else { return nil }
    let candidates = activeGroup.children.enumerated().compactMap { index, sibling -> (path: [Int], distance: Float)? in
      guard index != currentIndex else { return nil }
      let delta = center(of: sibling.rect)
      let primaryDistance =
        primaryAxis == .horizontal
        ? (delta.x - originCenter.x) * Float(direction)
        : (delta.y - originCenter.y) * Float(direction)
      let secondaryDistance =
        primaryAxis == .horizontal
        ? abs(delta.y - originCenter.y)
        : abs(delta.x - originCenter.x)
      let overlaps =
        primaryAxis == .horizontal
        ? min(current.rect.maxY, sibling.rect.maxY) > max(current.rect.minY, sibling.rect.minY)
        : min(current.rect.maxX, sibling.rect.maxX) > max(current.rect.minX, sibling.rect.minX)
      guard overlaps || primaryDistance >= secondaryDistance else { return nil }
      let separated =
        primaryAxis == .horizontal
        ? (direction < 0 ? sibling.rect.maxX <= current.rect.minX : sibling.rect.minX >= current.rect.maxX)
        : (direction < 0 ? sibling.rect.maxY <= current.rect.minY : sibling.rect.minY >= current.rect.maxY)
      guard separated else { return nil }
      return ([index], primaryDistance + secondaryDistance)
    }

    if let winner = candidates.min(by: { $0.distance < $1.distance }) {
      return currentPrefix + winner.path
    }

    return nil
  }

  private func center(of rect: Rect) -> Point {
    Point(x: rect.minX + rect.size.width / 2, y: rect.minY + rect.size.height / 2)
  }
}
