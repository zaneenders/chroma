import Observation

@MainActor
final class NodeScene {
  enum BuildError: Error {
    case unsupportedBlock
  }

  private enum Content {
    case text(Text)
    case button(Button)
    case color(Color)
    case spacer
    case stack(axis: StackLayout.Axis, spacing: Float, reversed: Bool, bottomAligned: Bool)
    case overlay
    case scope(CommandScope)
    case empty
    case list(FixedHeightList)
  }

  private enum Decoration {
    case layout(LayoutModifier.Operation)
    case fill(Color)
    case rounded(Color, CornerRadii)
    case border(Color, CornerRadii, Float)
    case clip
  }

  private enum LayoutContent: Equatable {
    case text(String, Float, Bool)
    case button(String, Float, EdgeInsets)
    case stack(StackLayout.Axis, Float, Bool, Bool)
    case overlay, scope, empty, color, spacer
    case list(Int, Float, Int)
  }

  private struct Measurement {
    var proposal: Size
    var metrics: FontMetrics
    var textScale: Float
    var size: Size
  }

  private struct Node {
    var content: Content
    var context: BlockContext
    var decorations: [Decoration] = []
    var decorationRects: [Rect] = []
    var outerRect: Rect = .zero
    var rect: Rect = .zero
    var visualBounds: Rect? = .zero
    var lines: [String] = []
    var lineMetrics: FontMetrics?
    var measurements: [Measurement] = []
    var visibleRange: Range<Int>?
    var offset: Float = 0
    var rowsDirty = true

    var layoutContent: LayoutContent {
      switch content {
      case .text(let text): .text(text.content, text.scale, text.wraps)
      case .button(let button): .button(button.label, button.fontScale, button.padding)
      case .stack(let axis, let spacing, let reversed, let bottom): .stack(axis, spacing, reversed, bottom)
      case .overlay: .overlay
      case .scope: .scope
      case .empty: .empty
      case .color: .color
      case .spacer: .spacer
      case .list(let list): .list(list.count, list.rowHeight, list.overscan)
      }
    }

    var layoutOperations: [LayoutModifier.Operation] {
      decorations.compactMap { if case .layout(let operation) = $0 { operation } else { nil } }
    }
  }

  private struct Description {
    var node: Node
    var children: [Description] = []
  }

  private(set) var measurements = 0
  private(set) var layouts = 0
  private(set) var preparations = 0
  private(set) var paintVisits = 0
  var slotCount: Int { store.slotCount }
  var liveCount: Int { store.liveCount }
  private var rowSubscriptions: [NodeID: FrameTrackingSubscription] = [:]
  var rowsAreValid: Bool { rowSubscriptions.values.allSatisfy(\.isActive) }
  var onChange: @MainActor @Sendable () -> Void = {}

  func resetTracking() {
    for subscription in rowSubscriptions.values { subscription.cancel() }
    rowSubscriptions = [:]
    onChange = {}
  }

  deinit { for subscription in rowSubscriptions.values { subscription.cancel() } }

  private var store = NodeStore<Node>()
  private var root: NodeID?
  private var layoutRect: Rect?
  private var layoutMetrics: FontMetrics?
  private var layoutDirty = true
  private var prepared = false

  func update(_ block: any Block, context: BlockContext) throws {
    let description = try lower(block, context: context)
    let old = root.flatMap { store.value(for: $0) }
    let changed = old.map { !Self.sameLayout($0, description.node) } ?? true
    if let root {
      store.update(root, value: Self.merge(old!, description.node))
    } else {
      root = store.insert(description.node)
    }
    layoutDirty = reconcile(description.children, of: root!) || changed || layoutDirty
    releaseRemovedRows()
    prepared = false
  }

  private func lower(_ block: any Block, context: BlockContext) throws -> Description {
    if let scoped = block as? ScopedBlock {
      return try lower(scoped.content, context: context.scoped(scoped.path))
    }
    if let modifier = block as? ContextModifier {
      var context = context
      switch modifier.operation {
      case .hover(let style): context.hoverStyle = style
      case .navigationIgnored: context.navigationIgnored = true
      }
      return try lower(modifier.content, context: context)
    }
    if let theme = block as? ThemeBlock {
      return try lower(theme.content, context: context.withTheme(theme.theme))
    }
    if let modifier = block as? LayoutModifier {
      var result = try lower(modifier.content, context: context)
      result.node.decorations.insert(.layout(modifier.operation), at: 0)
      return result
    }
    if let modifier = block as? PaintModifier {
      let decoration: Decoration
      var context = context
      switch modifier.operation {
      case .background(let block):
        guard let color = block as? Color else { throw BuildError.unsupportedBlock }
        decoration = .fill(color)
        context = context.backgroundContentContext
      case .roundedBackground(let color, let radii): decoration = .rounded(color, radii)
      case .border(let color, let radii, let width): decoration = .border(color, radii, width)
      case .clip: decoration = .clip
      }
      var result = try lower(modifier.content, context: context)
      result.node.decorations.insert(decoration, at: 0)
      return result
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
    if let color = block as? Color { return Description(node: Node(content: .color(color), context: context)) }
    if block is Spacer { return Description(node: Node(content: .spacer, context: context)) }
    if block is EmptyBlock { return Description(node: Node(content: .empty, context: context)) }
    if let stack = block as? VStack {
      return try lowerChildren(
        stack.scopedChildren,
        content: .stack(
          axis: .vertical, spacing: stack.spacing, reversed: stack.isLayoutReversed, bottomAligned: false),
        context: context)
    }
    if let stack = block as? HStack {
      return try lowerChildren(
        stack.scopedChildren,
        content: .stack(
          axis: .horizontal, spacing: stack.spacing, reversed: stack.isLayoutReversed,
          bottomAligned: stack.alignment == .bottom), context: context)
    }
    if let stack = block as? ZStack {
      return try lowerChildren(stack.scopedChildren, content: .overlay, context: context)
    }
    guard !(block is any PrimitiveBlock) else { throw BuildError.unsupportedBlock }
    return try lower(block.body, context: context)
  }

  private func lowerChildren(_ children: [any Block], content: Content, context: BlockContext) throws -> Description {
    Description(
      node: Node(content: content, context: context),
      children: try children.enumerated().map { index, child in
        try lower(child, context: context.childContext(for: child, at: index))
      })
  }

  private static func sameLayout(_ old: Node, _ new: Node) -> Bool {
    old.layoutContent == new.layoutContent && old.layoutOperations == new.layoutOperations
      && old.context.textScale == new.context.textScale
  }

  private static func merge(_ old: Node, _ new: Node) -> Node {
    var result = new
    result.outerRect = old.outerRect
    result.rect = old.rect
    result.decorationRects = old.decorationRects
    result.visualBounds = old.visualBounds
    if Self.sameLayout(old, new) {
      result.lines = old.lines
      result.lineMetrics = old.lineMetrics
      result.measurements = old.measurements
    }
    result.visibleRange = old.visibleRange
    result.offset = old.offset
    return result
  }

  @discardableResult
  private func reconcile(_ descriptions: [Description], of parent: NodeID, updatingRows: Bool = false) -> Bool {
    if !updatingRows, case .list = store.value(for: parent)!.content {
      layoutDirty = true
      return false
    }
    let previous = store.children(of: parent)!
    var changed = false
    let children = store.reconcileChildren(
      of: parent, with: descriptions.map { (StructuralKey($0.node.context.structuralPath), $0.node) },
      merge: { old, new in
        if !Self.sameLayout(old, new) { changed = true }
        return Self.merge(old, new)
      })!
    changed = children != previous || changed
    for (id, description) in zip(children, descriptions) {
      if reconcile(description.children, of: id) { changed = true }
    }
    if changed {
      var node = store.value(for: parent)!
      node.measurements = []
      store.update(parent, value: node)
    }
    return changed
  }

  @discardableResult
  func layout(in rect: Rect) throws -> Size {
    guard let root else { return .zero }
    let metrics = store.value(for: root)!.context.fontMetrics
    let needsPlacement = layoutDirty || layoutRect != rect || layoutMetrics != metrics
    let size = measure(root, proposal: rect.size)
    if needsPlacement {
      layouts += 1
      try place(root, in: rect)
      layoutDirty = false
      layoutRect = rect
      layoutMetrics = metrics
      prepared = false
    } else if !prepared {
      // Paint-only updates can change visual overflow without changing layout.
      refreshBounds(root)
    }
    return size
  }

  private func measure(_ id: NodeID, proposal: Size) -> Size {
    var node = store.value(for: id)!
    let metrics = node.context.fontMetrics
    if let cached = node.measurements.first(where: {
      $0.proposal == proposal && $0.metrics == metrics && $0.textScale == node.context.textScale
    }) {
      return cached.size
    }
    measurements += 1
    let size = measureDecorations(node, id: id, index: 0, proposal: proposal)
    node.measurements.append(
      Measurement(proposal: proposal, metrics: metrics, textScale: node.context.textScale, size: size))
    if node.measurements.count > 2 { node.measurements.removeFirst() }
    store.update(id, value: node)
    return size
  }

  private func measureDecorations(_ node: Node, id: NodeID, index: Int, proposal: Size) -> Size {
    if index < node.decorations.count {
      if case .layout(let operation) = node.decorations[index] {
        return LayoutModifier(content: EmptyBlock(), operation: operation).sizeThatFits(proposal, context: node.context)
        {
          measureDecorations(node, id: id, index: index + 1, proposal: $0)
        }
      }
      return measureDecorations(node, id: id, index: index + 1, proposal: proposal)
    }
    switch node.content {
    case .text(let text): return text.sizeThatFits(proposal, context: node.context)
    case .button(let button): return button.sizeThatFits(proposal, context: node.context)
    case .scope: return measure(store.children(of: id)![0], proposal: proposal)
    case .list, .color, .spacer: return proposal
    case .empty: return .zero
    case .overlay:
      return store.children(of: id)!.reduce(Size.zero) {
        let size = measure($1, proposal: proposal)
        return Size(width: max($0.width, size.width), height: max($0.height, size.height))
      }
    case .stack(let axis, let spacing, _, _):
      let sizes = stackSizes(id, axis: axis, spacing: spacing, proposal: proposal)
      var result = Size.zero
      result[keyPath: axis.main] =
        sizes.reduce(0) { $0 + $1[keyPath: axis.main] } + spacing * Float(max(0, sizes.count - 1))
      result[keyPath: axis.cross] = sizes.map { $0[keyPath: axis.cross] }.max() ?? 0
      return result
    }
  }

  private func expands(_ id: NodeID, axis: StackLayout.Axis) -> Bool {
    let node = store.value(for: id)!
    for decoration in node.decorations {
      if case .layout(.sizing(let x, let y)) = decoration { return (axis == .horizontal ? x : y) == .grow }
    }
    switch node.content {
    case .color, .spacer, .list: return true
    case .stack, .overlay: return store.children(of: id)!.contains { expands($0, axis: axis) }
    case .scope: return expands(store.children(of: id)![0], axis: axis)
    default: return false
    }
  }

  private func stackSizes(_ id: NodeID, axis: StackLayout.Axis, spacing: Float, proposal: Size) -> [Size] {
    let children = store.children(of: id)!
    var sizes = children.map { measure($0, proposal: proposal) }
    let flexible = children.map { expands($0, axis: axis) }
    let count = flexible.filter { $0 }.count
    let fixed = sizes.indices.filter { !flexible[$0] }.reduce(Float(0)) { $0 + sizes[$1][keyPath: axis.main] }
    for index in children.indices {
      if flexible[index] && count > 0 {
        var childProposal = proposal
        childProposal[keyPath: axis.main] =
          max(0, proposal[keyPath: axis.main] - fixed - spacing * Float(max(0, children.count - 1))) / Float(count)
        sizes[index] = measure(children[index], proposal: childProposal)
        sizes[index][keyPath: axis.main] = childProposal[keyPath: axis.main]
      }
      let child = store.value(for: children[index])!
      if case .spacer = child.content, child.decorations.isEmpty { sizes[index][keyPath: axis.cross] = 0 }
    }
    return sizes
  }

  private func place(_ id: NodeID, in outerRect: Rect) throws {
    var node = store.value(for: id)!
    node.outerRect = outerRect
    var rect = outerRect
    node.decorationRects = node.decorations.map { decoration in
      let current = rect
      if case .layout(.padding(let insets)) = decoration {
        rect = Rect(
          x: rect.minX + insets.leading, y: rect.minY + insets.top,
          width: rect.size.width - insets.leading - insets.trailing,
          height: rect.size.height - insets.top - insets.bottom)
      }
      return current
    }
    let textChanged = node.rect.size != rect.size || node.lineMetrics != node.context.fontMetrics
    node.rect = rect
    switch node.content {
    case .text(let text):
      if textChanged || node.lines.isEmpty {
        let cell = node.context.fontMetrics.cellAdvance * text.scale * node.context.textScale
        let columns =
          text.wraps && rect.size.width.isFinite && cell.isFinite && cell > 0
          ? Int(min(Float(Int32.max), max(1, rect.size.width / cell))) : nil
        node.lines = TextLayout(text.content, columns: columns).lines.map(\.text)
        node.lineMetrics = node.context.fontMetrics
      }
    case .scope: try place(store.children(of: id)![0], in: rect)
    case .list(let list):
      let offset = node.context.interaction.resolveScroll(
        id: node.context.widgetID, viewport: rect,
        contentSize: Size(width: rect.size.width, height: Float(list.count) * list.rowHeight),
        controller: nil, sticksToBottom: false
      ).y
      let range = list.visibleRange(offset: offset, height: rect.size.height)
      if range != node.visibleRange || node.rowsDirty {
        var subscriptions: [FrameTrackingSubscription] = []
        var committed = false
        defer { if !committed { for subscription in subscriptions { subscription.cancel() } } }
        let descriptions = try range.map { index in
          let subscription = FrameTrackingSubscription(onChange)
          subscriptions.append(subscription)
          return try withObservationTracking(options: .didSet) {
            subscription.trackCancellation()
            return try lower(list.row(index), context: node.context.scoped([.key(list.key(index))]))
          } onChange: { [weak subscription] event in
            event.cancel()
            if let callback = subscription?.takeCallback() { ObservationDelivery.enqueue(callback) }
          }
        }
        reconcile(descriptions, of: id, updatingRows: true)
        for (child, subscription) in zip(store.children(of: id)!, subscriptions) {
          rowSubscriptions[child]?.cancel()
          rowSubscriptions[child] = subscription
        }
        releaseRemovedRows()
        committed = true
        node.rowsDirty = false
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
    case .overlay:
      for child in store.children(of: id)! {
        try place(child, in: Rect(origin: rect.origin, size: measure(child, proposal: rect.size)))
      }
    case .button, .color, .spacer, .empty: break
    case .stack(let axis, let spacing, let reversed, let bottomAligned):
      let sizes = stackSizes(id, axis: axis, spacing: spacing, proposal: rect.size)
      var cursor = axis == .horizontal ? rect.minX : rect.minY
      if reversed { cursor += rect.size[keyPath: axis.main] }
      for (child, size) in zip(store.children(of: id)!, sizes) {
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
    updateBounds(id)
  }

  private func releaseRemovedRows() {
    for id in rowSubscriptions.keys where !store.contains(id) {
      rowSubscriptions.removeValue(forKey: id)?.cancel()
    }
  }

  private func refreshBounds(_ id: NodeID) {
    var node = store.value(for: id)!
    var rect = node.outerRect
    node.decorationRects = node.decorations.map { decoration in
      let current = rect
      if case .layout(.padding(let insets)) = decoration {
        rect = Rect(
          x: rect.minX + insets.leading, y: rect.minY + insets.top,
          width: rect.size.width - insets.leading - insets.trailing,
          height: rect.size.height - insets.top - insets.bottom)
      }
      return current
    }
    store.update(id, value: node)
    for child in store.children(of: id)! { refreshBounds(child) }
    updateBounds(id)
  }

  private func union(_ a: Rect?, _ b: Rect?) -> Rect? {
    guard let a, let b else { return nil }
    if a.size == .zero { return b }
    if b.size == .zero { return a }
    return Rect(
      x: min(a.minX, b.minX), y: min(a.minY, b.minY),
      width: max(a.maxX, b.maxX) - min(a.minX, b.minX), height: max(a.maxY, b.maxY) - min(a.minY, b.minY))
  }

  private func expanded(_ rect: Rect, by amount: Float) -> Rect? {
    guard [rect.minX, rect.minY, rect.size.width, rect.size.height, amount].allSatisfy(\.isFinite),
      rect.size.width >= 0, rect.size.height >= 0, amount >= 0
    else { return nil }
    return Rect(
      x: rect.minX - amount, y: rect.minY - amount,
      width: rect.size.width + 2 * amount, height: rect.size.height + 2 * amount)
  }

  private func textBounds(_ lines: [String], in rect: Rect, scale: Float, metrics: FontMetrics) -> Rect? {
    guard scale.isFinite, scale > 0 else { return nil }
    let width = lines.map { Float(max(0, $0.count - 1)) * metrics.cellAdvance + metrics.glyphWidth }.max() ?? 0
    return expanded(
      Rect(
        x: rect.minX, y: rect.minY, width: width * scale,
        height: (Float(max(0, lines.count - 1)) * metrics.lineAdvance + metrics.glyphHeight) * scale), by: 0)
  }

  private func updateBounds(_ id: NodeID) {
    var node = store.value(for: id)!
    var bounds: Rect? = .zero
    switch node.content {
    case .text(let text):
      bounds = textBounds(
        node.lines, in: node.rect, scale: text.scale * node.context.textScale, metrics: node.context.fontMetrics)
      if !node.context.focusLeafClaimed && !node.context.navigationIgnored {
        bounds = union(bounds, expanded(node.rect, by: 2))
      }
    case .button(let button):
      let textRect = Rect(
        x: node.rect.minX + button.padding.leading, y: node.rect.minY + button.padding.top, width: 0, height: 0)
      bounds = union(
        expanded(node.rect, by: max(2, (button.style ?? node.context.theme.button).borderWidth)),
        textBounds(
          button.label.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
          in: textRect, scale: button.fontScale * node.context.textScale, metrics: node.context.fontMetrics))
    case .color: bounds = expanded(node.rect, by: 2)
    case .empty, .spacer: break
    case .list, .stack, .overlay, .scope:
      for child in store.children(of: id)! { bounds = union(bounds, store.value(for: child)!.visualBounds) }
      if case .list = node.content { bounds = bounds?.intersection(node.rect) ?? node.rect }
    }
    for (decoration, rect) in zip(node.decorations, node.decorationRects).reversed() {
      switch decoration {
      case .fill, .rounded: bounds = union(bounds, expanded(rect, by: 0))
      case .border(_, _, let width): bounds = union(bounds, expanded(rect, by: max(0, width)))
      case .clip: bounds = bounds.map { $0.intersection(rect) ?? .zero } ?? rect
      case .layout: break
      }
    }
    node.visualBounds = bounds
    store.update(id, value: node)
  }

  func prepare(viewport: Size) {
    precondition(layoutRect != nil, "Layout must precede interaction preparation")
    guard let root, let node = store.value(for: root) else { return }
    preparations += 1
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
    let interaction = node.context.interaction
    var clipCount = 0
    for (decoration, rect) in zip(node.decorations, node.decorationRects) {
      if case .clip = decoration {
        interaction.pushClip(rect)
        clipCount += 1
      }
    }
    defer { for _ in 0..<clipCount { interaction.popClip() } }
    switch node.content {
    case .text, .color:
      if !node.context.focusLeafClaimed && !node.context.navigationIgnored {
        _ = node.context.buttonState(id: node.context.widgetID, in: node.rect)
      }
    case .button(let button):
      _ = node.context.buttonState(
        id: button.id ?? node.context.widgetID, in: node.rect, role: button.role, action: button.action)
    case .scope(let scope): scope.prepare(in: node.rect, context: node.context) { prepare(store.children(of: id)![0]) }
    case .list:
      interaction.registerScrollInput(id: node.context.widgetID, rect: node.rect)
      interaction.beginGroup(rect: node.rect, axis: .vertical, scrollID: node.context.widgetID)
      interaction.pushClip(node.rect)
      for child in store.children(of: id)! { prepare(child) }
      interaction.popClip()
      interaction.endGroup()
    case .empty, .spacer: break
    case .stack(let axis, _, _, _):
      interaction.beginGroup(rect: node.rect, axis: axis == .horizontal ? .horizontal : .vertical)
      for child in store.children(of: id)! { prepare(child) }
      interaction.endGroup()
    case .overlay:
      interaction.beginGroup(rect: node.rect)
      for child in store.children(of: id)! { prepare(child) }
      interaction.endGroup()
    }
  }

  func dispatch(_ input: InputState) throws {
    processInput(input)
    try refreshScroll()
    prepareIfNeeded()
  }

  func processInput(_ input: InputState) {
    precondition(prepared, "Interaction preparation must precede input")
    guard let root, let node = store.value(for: root) else { return }
    node.context.interaction.processInput(input)
    node.context.interaction.finishInput()
  }

  func refreshScroll() throws {
    guard let root, scrollChanged(root) else { return }
    prepared = false
    try place(root, in: layoutRect!)
  }

  func prepareIfNeeded(viewport: Size? = nil) {
    guard !prepared, let root, let node = store.value(for: root) else { return }
    prepare(viewport: viewport ?? node.context.interaction.viewport.size)
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

  func paint(cullingEnabled: Bool = true) -> DrawList {
    precondition(prepared, "Interaction preparation must precede paint")
    var list = DrawList()
    if let root {
      paint(
        root, into: &list, clip: store.value(for: root)!.context.interaction.viewport, cullingEnabled: cullingEnabled)
    }
    return list
  }

  private func paint(_ id: NodeID, into list: inout DrawList, clip: Rect, cullingEnabled: Bool) {
    let node = store.value(for: id)!
    if cullingEnabled, let bounds = node.visualBounds, bounds.intersection(clip) == nil { return }
    paintVisits += 1
    paintDecorations(node, id: id, index: 0, into: &list, clip: clip, cullingEnabled: cullingEnabled)
  }

  private func paintDecorations(
    _ node: Node, id: NodeID, index: Int, into list: inout DrawList, clip: Rect, cullingEnabled: Bool
  ) {
    guard index < node.decorations.count else {
      paintContent(node, id: id, into: &list, clip: clip, cullingEnabled: cullingEnabled)
      return
    }
    let rect = node.decorationRects[index]
    var clip = clip
    switch node.decorations[index] {
    case .fill(let color): list.fillRect(rect, color: color)
    case .rounded(let color, let radii): list.fillRoundedRect(rect, radii: radii, color: color)
    case .clip:
      clip = clip.intersection(rect) ?? .zero
      list.pushClip(rect)
    case .layout, .border: break
    }
    paintDecorations(node, id: id, index: index + 1, into: &list, clip: clip, cullingEnabled: cullingEnabled)
    switch node.decorations[index] {
    case .border(let color, let radii, let width):
      if radii == .zero {
        list.strokeRect(rect, width: width, color: color)
      } else {
        list.strokeRoundedRect(rect, radii: radii, width: width, color: color)
      }
    case .clip: list.popClip()
    default: break
    }
  }

  private func paintContent(_ node: Node, id: NodeID, into list: inout DrawList, clip: Rect, cullingEnabled: Bool) {
    switch node.content {
    case .text(let text):
      let scale = text.scale * node.context.textScale
      for (row, line) in node.lines.enumerated() {
        list.text(
          line,
          at: Point(
            x: node.rect.minX,
            y: node.rect.minY + Float(row) * node.context.fontMetrics.lineAdvance * scale), color: text.color,
          scale: scale)
      }
      paintHighlight(node, into: &list)
    case .color(let color):
      list.fillRect(node.rect, color: color)
      paintHighlight(node, into: &list)
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
      let clip = clip.intersection(node.rect) ?? .zero
      for child in store.children(of: id)! { paint(child, into: &list, clip: clip, cullingEnabled: cullingEnabled) }
      list.popClip()
    case .empty, .spacer: break
    case .stack, .overlay, .scope:
      for child in store.children(of: id)! { paint(child, into: &list, clip: clip, cullingEnabled: cullingEnabled) }
    }
  }

  private func paintHighlight(_ node: Node, into list: inout DrawList) {
    if !node.context.focusLeafClaimed && !node.context.navigationIgnored {
      BlockEngine.drawHighlight(for: node.context.widgetID, into: &list, in: node.rect, context: node.context)
    }
  }
}
