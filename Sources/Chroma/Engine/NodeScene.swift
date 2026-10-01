@MainActor
final class NodeScene {
  enum BuildError: Error {
    case unsupportedBlock
  }

  private enum Content {
    case text(Text)
    case button(Button)
    case stack(axis: StackLayout.Axis, spacing: Float, reversed: Bool, bottomAligned: Bool)
    case scope(CommandScope)
    case empty
    case list(FixedHeightList)
  }

  private struct Node {
    var content: Content
    var context: BlockContext
    var rect: Rect = .zero
    var lines: [String] = []
    var measured: Size = .zero
    var visibleRange: Range<Int>?
    var offset: Float = 0
  }

  private struct Description {
    var node: Node
    var children: [Description] = []
  }

  private(set) var rowBuildRevision = 0
  private var store = NodeStore<Node>()
  private var root: NodeID?
  private var laidOut = false
  private var prepared = false

  func update(_ block: any Block, context: BlockContext) throws {
    let description = try lower(block, context: context)
    let node = description.node
    if let root {
      store.update(root, value: node)
    } else {
      root = store.insert(node)
    }
    reconcile(description.children, of: root!)
    laidOut = false
    prepared = false
  }

  private func lower(_ block: any Block, context: BlockContext) throws -> Description {
    if let scoped = block as? ScopedBlock {
      return try lower(scoped.content, context: context.scoped(scoped.path))
    }
    if let scope = block as? CommandScope {
      return Description(
        node: Node(content: .scope(scope), context: context),
        children: [try lower(scope.content, context: context)])
    }
    let context = context.scoped([.component(ObjectIdentifier(type(of: block)))])
    if let list = block as? FixedHeightList {
      return Description(node: Node(content: .list(list), context: context))
    }
    if let text = block as? Text {
      guard !text.isSelectable else { throw BuildError.unsupportedBlock }
      return Description(node: Node(content: .text(text), context: context))
    }
    if let button = block as? Button {
      return Description(node: Node(content: .button(button), context: context))
    }
    if block is EmptyBlock {
      return Description(node: Node(content: .empty, context: context))
    }
    if let stack = block as? VStack {
      return try lowerStack(
        stack.scopedChildren, axis: .vertical, spacing: stack.spacing,
        reversed: stack.isLayoutReversed, bottomAligned: false, context: context)
    }
    if let stack = block as? HStack {
      return try lowerStack(
        stack.scopedChildren, axis: .horizontal, spacing: stack.spacing,
        reversed: stack.isLayoutReversed, bottomAligned: stack.alignment == .bottom, context: context)
    }
    guard !(block is any PrimitiveBlock) else { throw BuildError.unsupportedBlock }
    return try lower(block.body, context: context)
  }

  private func lowerStack(
    _ children: [any Block], axis: StackLayout.Axis, spacing: Float, reversed: Bool, bottomAligned: Bool,
    context: BlockContext
  ) throws -> Description {
    let children = try children.enumerated().map { index, child in
      try lower(child, context: context.childContext(for: child, at: index))
    }
    return Description(
      node: Node(
        content: .stack(axis: axis, spacing: spacing, reversed: reversed, bottomAligned: bottomAligned),
        context: context),
      children: children)
  }

  private func reconcile(_ descriptions: [Description], of parent: NodeID) {
    let children = store.reconcileChildren(
      of: parent, with: descriptions.map { (StructuralKey($0.node.context.structuralPath), $0.node) })!
    for (id, description) in zip(children, descriptions) {
      reconcile(description.children, of: id)
    }
  }

  @discardableResult
  func layout(in rect: Rect) throws -> Size {
    guard let root else { return .zero }
    laidOut = false
    prepared = false
    let size = measure(root, proposal: rect.size)
    try place(root, in: rect)
    laidOut = true
    prepared = false
    return size
  }

  private func measure(_ id: NodeID, proposal: Size) -> Size {
    var node = store.value(for: id)!
    switch node.content {
    case .text(let text):
      node.measured = text.sizeThatFits(proposal, context: node.context)
    case .button(let button):
      node.measured = button.sizeThatFits(proposal, context: node.context)
    case .scope:
      node.measured = measure(store.children(of: id)![0], proposal: proposal)
    case .list:
      node.measured = proposal
    case .empty: node.measured = .zero
    case .stack(let axis, let spacing, _, _):
      let sizes = store.children(of: id)!.map { measure($0, proposal: proposal) }
      node.measured = .zero
      node.measured[keyPath: axis.main] =
        sizes.reduce(0) { $0 + $1[keyPath: axis.main] }
        + spacing * Float(max(0, sizes.count - 1))
      node.measured[keyPath: axis.cross] = sizes.map { $0[keyPath: axis.cross] }.max() ?? 0
    }
    store.update(id, value: node)
    return node.measured
  }

  private func place(_ id: NodeID, in rect: Rect) throws {
    var node = store.value(for: id)!
    node.rect = rect
    switch node.content {
    case .text(let text):
      let cell = node.context.fontMetrics.cellAdvance * text.scale * node.context.textScale
      let columns =
        text.wraps && rect.size.width.isFinite && cell.isFinite && cell > 0
        ? Int(min(Float(Int32.max), max(1, rect.size.width / cell))) : nil
      node.lines = TextLayout(text.content, columns: columns).lines.map(\.text)
    case .scope:
      try place(store.children(of: id)![0], in: rect)
    case .list(let list):
      let interaction = node.context.interaction
      let scrollID = node.context.widgetID
      let offset = interaction.resolveScroll(
        id: scrollID, viewport: rect,
        contentSize: Size(width: rect.size.width, height: Float(list.count) * list.rowHeight),
        controller: nil, sticksToBottom: false
      ).y
      let range = list.visibleRange(offset: offset, height: rect.size.height)
      if range != node.visibleRange {
        let descriptions = try range.map { index in
          try lower(list.row(index), context: node.context.scoped([.key(list.key(index))]))
        }
        rowBuildRevision += 1
        reconcile(descriptions, of: id)
        node.visibleRange = range
      }
      node.offset = offset
      for (index, child) in zip(range, store.children(of: id)!) {
        let rowRect = Rect(
          x: rect.minX, y: rect.minY + Float(index) * list.rowHeight - offset,
          width: rect.size.width, height: list.rowHeight)
        _ = measure(child, proposal: rowRect.size)
        try place(child, in: rowRect)
      }
    case .button, .empty: break
    case .stack(let axis, let spacing, let reversed, let bottomAligned):
      var cursor = axis == .horizontal ? rect.minX : rect.minY
      if reversed { cursor += rect.size[keyPath: axis.main] }
      for child in store.children(of: id)! {
        let size = store.value(for: child)!.measured
        let extent = size[keyPath: axis.main]
        if reversed { cursor -= extent }
        let origin =
          axis == .horizontal
          ? Point(x: cursor, y: bottomAligned ? rect.maxY - size.height : rect.minY)
          : Point(x: rect.minX, y: cursor)
        try place(child, in: Rect(origin: origin, size: size))
        cursor += reversed ? -spacing : extent + spacing
      }
    }
    store.update(id, value: node)
  }

  func prepare(viewport: Size) {
    precondition(laidOut, "Layout must precede interaction preparation")
    guard let root, let node = store.value(for: root) else { return }
    let interaction = node.context.interaction
    interaction.viewport = Rect(origin: .zero, size: viewport)
    interaction.refreshingRegistrations = true
    defer { interaction.refreshingRegistrations = false }
    interaction.beginFrame(input: interaction.input, processingInput: false)
    prepare(root)
    interaction.endFrame()
    prepared = true
  }

  private func prepare(_ id: NodeID) {
    let node = store.value(for: id)!
    switch node.content {
    case .text:
      if !node.context.focusLeafClaimed && !node.context.navigationIgnored {
        _ = node.context.buttonState(id: node.context.widgetID, in: node.rect)
      }
    case .button(let button):
      _ = node.context.buttonState(
        id: button.id ?? node.context.widgetID, in: node.rect, role: button.role, action: button.action)
    case .scope(let scope):
      scope.prepare(in: node.rect, context: node.context) {
        prepare(store.children(of: id)![0])
      }
    case .list:
      let interaction = node.context.interaction
      interaction.registerScrollInput(id: node.context.widgetID, rect: node.rect)
      interaction.beginGroup(rect: node.rect, axis: .vertical, scrollID: node.context.widgetID)
      interaction.pushClip(node.rect)
      for child in store.children(of: id)! { prepare(child) }
      interaction.popClip()
      interaction.endGroup()
    case .empty: break
    case .stack(let axis, _, _, _):
      node.context.interaction.beginGroup(
        rect: node.rect, axis: axis == .horizontal ? .horizontal : .vertical)
      for child in store.children(of: id)! { prepare(child) }
      node.context.interaction.endGroup()
    }
  }

  func dispatch(_ input: InputState) throws {
    precondition(prepared, "Interaction preparation must precede input")
    guard let root, let node = store.value(for: root) else { return }
    node.context.interaction.processInput(input)
    node.context.interaction.finishInput()
    try refreshScroll()
    prepareIfNeeded()
  }

  func processInput(_ input: InputState) {
    precondition(prepared)
    guard let root, let node = store.value(for: root) else { return }
    node.context.interaction.processInput(input)
    node.context.interaction.finishInput()
  }

  func refreshScroll() throws {
    guard let root, let node = store.value(for: root), scrollChanged(root) else { return }
    prepared = false
    try place(root, in: node.rect)
  }

  func prepareIfNeeded() {
    guard !prepared, let root, let node = store.value(for: root) else { return }
    prepare(viewport: node.context.interaction.viewport.size)
  }

  private func scrollChanged(_ id: NodeID) -> Bool {
    let node = store.value(for: id)!
    if case .list = node.content,
      node.context.interaction.scrollStates[node.context.widgetID]?.offset.y != node.offset
    {
      return true
    }
    return store.children(of: id)!.contains { scrollChanged($0) }
  }

  func paint() -> DrawList {
    precondition(prepared, "Interaction preparation must precede paint")
    var list = DrawList()
    if let root { paint(root, into: &list) }
    return list
  }

  private func paint(_ id: NodeID, into list: inout DrawList) {
    let node = store.value(for: id)!
    switch node.content {
    case .text(let text):
      let scale = text.scale * node.context.textScale
      for (row, line) in node.lines.enumerated() {
        list.text(
          line,
          at: Point(
            x: node.rect.minX,
            y: node.rect.minY + Float(row)
              * node.context.fontMetrics.lineAdvance * scale), color: text.color, scale: scale)
      }
      if !node.context.focusLeafClaimed && !node.context.navigationIgnored {
        BlockEngine.drawHighlight(
          for: node.context.widgetID, into: &list, in: node.rect, context: node.context)
      }
    case .button(let button):
      let interaction = node.context.interaction
      let id = button.id ?? node.context.widgetID
      let state = interaction.untrackedLeafState
      button.paint(
        into: &list, in: node.rect, context: node.context,
        state: ButtonState(
          hovered: state.hovered == id, focused: state.selected == id,
          held: state.pressed == id && interaction.input.pointerDown, clicked: false))
    case .list:
      list.pushClip(node.rect)
      for child in store.children(of: id)! { paint(child, into: &list) }
      list.popClip()
    case .empty: break
    case .stack, .scope:
      for child in store.children(of: id)! { paint(child, into: &list) }
    }
  }
}
