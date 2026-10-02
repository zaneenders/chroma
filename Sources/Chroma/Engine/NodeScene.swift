import Observation

@MainActor
final class NodeScene {
  enum BuildError: Error {
    case unsupportedBlock
  }

  private enum Content {
    case text(Text)
    case button(Button)
    case editor(TextEditor)
    case image(Image)
    case progress(ProgressIndicator)
    case marquee(MarqueeText)
    case color(Color)
    case spacer
    case stack(axis: StackLayout.Axis, spacing: Float, reversed: Bool, bottomAligned: Bool)
    case interactive(any NodeInteractive)
    case background
    case scroll(ScrollView)
    case group(String?)
    case trailing(Float)
    case element(any LifecycleElement)
    case overlay
    case tuple
    case scope(CommandScope)
    case boundary(UpdateBoundary)
    case empty
    case list(FixedHeightList)
    case variableList(VariableHeightList)
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
    case editor(Float, ClosedRange<Int>, Bool, Float)
    case image(Size)
    case progress(Float)
    case marquee(String, Float)
    case stack(StackLayout.Axis, Float, Bool, Bool)
    case interactive, background, scroll, group, element
    case trailing(Float)
    case overlay, tuple, scope, boundary, empty, color, spacer
    case list(Int, Float, Int)
    case variableList(Int, Float, Int)
  }

  private struct Measurement {
    var proposal: Size
    var metrics: FontMetrics
    var textScale: Float
    var size: Size
  }

  private struct Node {
    var phase: InteractionPhase = .idle
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
    var textLayouts: [(columns: Int?, layout: TextLayout)] = []
    var selectionLayout: PlainTextLayout?
    var editorLayout: TextEditorLayout?
    var editorText = ""
    var editorDirty = true
    var rowIndices: [Int] = []
    var rowKeys: [StructuralKey] = []
    var visibleRange: Range<Int>?
    var anchorKey: StructuralKey?
    var anchorIndex: Int = 0
    var anchorOffset: Double = 0
    var heightIndex: VariableHeightIndex?
    var measuredWidth: Float?
    var measuredMetrics: FontMetrics?
    var measuredTextScale: Float?
    var scrollOffset: Point = .zero
    var contentSize: Size = .zero
    var offset: Float = 0
    var rowsDirty = true
    var panelDirty = true

    var layoutContent: LayoutContent {
      switch content {
      case .text(let text): .text(text.content, text.scale, text.wraps)
      case .button(let button): .button(button.label, button.fontScale, button.padding)
      case .editor(let editor): .editor(editor.fontScale, editor.lineLimits, editor.singleLine, editor.padding)
      case .image(let image): .image(image.resource.size)
      case .progress(let progress): .progress(progress.diameter)
      case .marquee(let marquee): .marquee(marquee.text, marquee.fontScale)
      case .stack(let axis, let spacing, let reversed, let bottom): .stack(axis, spacing, reversed, bottom)
      case .interactive: .interactive
      case .background: .background
      case .scroll: .scroll
      case .group: .group
      case .trailing(let spacing): .trailing(spacing)
      case .element: .element
      case .overlay: .overlay
      case .tuple: .tuple
      case .scope: .scope
      case .boundary: .boundary
      case .empty: .empty
      case .color: .color
      case .spacer: .spacer
      case .list(let list): .list(list.count, list.rowHeight, list.overscan)
      case .variableList(let list): .variableList(list.count, list.estimatedHeight, list.overscan)
      }
    }

    var interactionClips: [Int] {
      var layouts = 0
      return decorations.compactMap {
        switch $0 {
        case .layout:
          layouts += 1
          return nil
        case .clip: return layouts
        default: return nil
        }
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

  private(set) var textLayoutBuilds = 0
  private(set) var measurements = 0
  private(set) var layouts = 0
  private(set) var preparations = 0
  private(set) var paintVisits = 0
  var slotCount: Int { store.slotCount }
  var liveCount: Int { store.liveCount }
  private struct TrackedDescription {
    var description: Description
    var subscription: FrameTrackingSubscription
  }

  private struct Boundary {
    var content: @MainActor () -> any Block
    var context: BlockContext
    var subscription: FrameTrackingSubscription
  }

  // A virtual row can itself be a panel; their subscriptions must remain independent.
  private struct BoundaryID: Hashable {
    var node: NodeID
    var isPanel: Bool
  }

  private var editorSubscriptions: [NodeID: FrameTrackingSubscription] = [:]
  var editorTextIsValid: Bool { editorSubscriptions.values.allSatisfy(\.isActive) }
  private var boundaries: [BoundaryID: Boundary] = [:]
  var boundariesAreValid: Bool { boundaries.values.allSatisfy { $0.subscription.isActive } }
  var onChange: @MainActor @Sendable () -> Void = {}
  private(set) var boundaryBuilds = 0

  func resetTracking() {
    for subscription in editorSubscriptions.values { subscription.cancel() }
    editorSubscriptions = [:]
    for boundary in boundaries.values { boundary.subscription.cancel() }
    boundaries = [:]
    onChange = {}
  }

  deinit {
    for subscription in editorSubscriptions.values { subscription.cancel() }
    for boundary in boundaries.values { boundary.subscription.cancel() }
  }

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
    releaseRemovedBoundaries()
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
        guard let color = block as? Color else {
          return Description(node: Node(content: .background, context: context), children: [
            try lower(block, context: context.backgroundContext),
            try lower(modifier.content, context: context.backgroundContentContext),
          ])
        }
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
    if let boundary = block as? UpdateBoundary {
      return Description(node: Node(content: .boundary(boundary), context: context))
    }
    if let scope = block as? CommandScope {
      return Description(
        node: Node(content: .scope(scope), context: context),
        children: [try lower(scope.content, context: context)])
    }
    if let target = block as? FocusTargetBlock {
      var context = context
      context.focusTargets.append(target.target)
      return try lower(target.content, context: context)
    }
    let context = context.scoped([.component(ObjectIdentifier(type(of: block)))])
    if let list = block as? VariableHeightList {
      return Description(node: Node(content: .variableList(list), context: context))
    }
    if let list = block as? FixedHeightList {
      return Description(node: Node(content: .list(list), context: context))
    }
    if let text = block as? Text {
      return Description(node: Node(content: .text(text), context: context))
    }
    if let image = block as? Image { return Description(node: Node(content: .image(image), context: context)) }
    if let progress = block as? ProgressIndicator {
      return Description(node: Node(content: .progress(progress), context: context))
    }
    if let marquee = block as? MarqueeText {
      return Description(node: Node(content: .marquee(marquee), context: context))
    }
    if let editor = block as? TextEditor {
      return Description(node: Node(content: .editor(editor), context: context))
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
    if let interactive = block as? any NodeInteractive {
      return Description(node: Node(content: .interactive(interactive), context: context))
    }
    if let scroll = block as? ScrollView, let rows = scroll.nodeRows {
      return Description(node: Node(content: .variableList(rows), context: context))
    }
    if let scroll = block as? ScrollView, let content = scroll.nodeContent {
      return Description(node: Node(content: .scroll(scroll), context: context), children: [try lower(content, context: context)])
    }
    if let group = block as? Group {
      return Description(node: Node(content: .group(group.name), context: context), children: [try lower(group.content, context: context)])
    }
    if let row = block as? any NodeTrailingControlsRow {
      return Description(node: Node(content: .trailing(row.nodeSpacing), context: context), children: [
        try lower(row.nodeInput, context: context.childScope(0)),
        try lower(row.nodeControls, context: context.childScope(1)),
      ])
    }
    if let element = block as? any LifecycleElement {
      return Description(node: Node(content: .element(element), context: context))
    }
    if let tuple = block as? TupleBlock {
      return try lowerChildren(tuple.scopedChildren, content: .tuple, context: context)
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
    if case .element = new.content { return false }
    return old.layoutContent == new.layoutContent && old.layoutOperations == new.layoutOperations
      && old.context.textScale == new.context.textScale
  }

  private static func sameInteraction(_ old: Node, _ new: Node) -> Bool {
    if case .text(let previous) = old.content, case .text(let current) = new.content,
      previous.isSelectable != current.isSelectable || previous.selectionID != current.selectionID
    { return false }
    switch (old.content, new.content) {
    case (.text, .text), (.image, .image), (.progress, .progress), (.marquee, .marquee), (.color, .color),
      (.empty, .empty), (.spacer, .spacer), (.stack, .stack), (.overlay, .overlay),
      (.tuple, .tuple):
      return old.context.widgetID == new.context.widgetID
        && old.context.navigationIgnored == new.context.navigationIgnored
        && old.context.focusLeafClaimed == new.context.focusLeafClaimed
        && old.context.focusTargets.map(ObjectIdentifier.init) == new.context.focusTargets.map(ObjectIdentifier.init)
        && old.interactionClips == new.interactionClips
    default: return false
    }
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
      result.textLayouts = old.textLayouts
      result.selectionLayout = old.selectionLayout
      result.editorLayout = old.editorLayout
    }
    if case .variableList(let previous) = old.content,
      case .variableList(let current) = new.content,
      previous.snapshotIdentity == current.snapshotIdentity,
      previous.count == current.count,
      previous.estimatedHeight == current.estimatedHeight
    {
      result.heightIndex = old.heightIndex
      result.measuredWidth = old.measuredWidth
      result.measuredMetrics = old.measuredMetrics
      result.measuredTextScale = old.measuredTextScale
    }
    result.anchorKey = old.anchorKey
    result.anchorIndex = old.anchorIndex
    result.anchorOffset = old.anchorOffset
    result.rowIndices = old.rowIndices
    result.rowKeys = old.rowKeys
    result.visibleRange = old.visibleRange
    result.scrollOffset = old.scrollOffset
    result.contentSize = old.contentSize
    result.offset = old.offset
    if case .editor = old.content, case .editor = new.content { result.editorText = old.editorText }
    return result
  }

  @discardableResult
  private func reconcile(_ descriptions: [Description], of parent: NodeID, updatingRows: Bool = false) -> Bool {
    if !updatingRows {
      switch store.value(for: parent)!.content {
      case .interactive, .list, .variableList, .boundary:
        layoutDirty = true
        return false
      default: break
      }
    }
    let previous = store.children(of: parent)!
    var changed = false
    let children = store.reconcileChildren(
      of: parent, with: descriptions.map { (StructuralKey($0.node.context.structuralPath), $0.node) },
      merge: { old, new in
        if !Self.sameLayout(old, new) { changed = true }
        if !Self.sameInteraction(old, new) { prepared = false }
        return Self.merge(old, new)
      })!
    if children != previous { prepared = false }
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
    try installPanels(root)
    refreshEditorText()
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
    let cached = store.withValue(for: id) { value in
      value.measurements.first {
        $0.proposal == proposal && $0.metrics == value.context.fontMetrics && $0.textScale == value.context.textScale
      }
    }
    if let cached { return cached.size }
    let node = store.value(for: id)!
    let metrics = node.context.fontMetrics
    measurements += 1
    let size = measureDecorations(node, id: id, index: 0, proposal: proposal)
    let measurement = Measurement(proposal: proposal, metrics: metrics, textScale: node.context.textScale, size: size)
    store.modify(id) {
      $0.measurements.append(measurement)
      if $0.measurements.count > 2 { $0.measurements.removeFirst() }
    }
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
    case .image(let image): return image.sizeThatFits(proposal, context: node.context)
    case .progress(let progress): return progress.sizeThatFits(proposal, context: node.context)
    case .marquee(let marquee): return marquee.sizeThatFits(proposal, context: node.context)
    case .text(let text):
      guard text.wraps else { return text.sizeThatFits(proposal, context: node.context) }
      let cell = node.context.fontMetrics.cellAdvance * text.scale * node.context.textScale
      let columns = proposal.width.isFinite && cell.isFinite && cell > 0
        ? Int(min(Float(Int32.max), max(1, proposal.width / cell))) : nil
      let layout = retainedTextLayout(id, text: text.content, columns: columns)
      return Size(width: proposal.width, height: Float(layout.lines.count) * node.context.fontMetrics.lineAdvance * text.scale * node.context.textScale)
    case .button(let button): return button.sizeThatFits(proposal, context: node.context)
    case .editor(let editor):
      return editor.sizeThatFits(
        proposal, context: node.context,
        layout: editorTextLayout(
          id, editor: editor, text: node.editorText, width: proposal.width, context: node.context))
    case .element(let element): return element.sizeThatFits(proposal, context: node.context)
    case .trailing(let spacing):
      let sizes = trailingSizes(id, spacing: spacing, proposal: proposal)
      return Size(width: proposal.width, height: max(sizes.0.height, sizes.1.height))
    case .background: return measure(store.children(of: id)![1], proposal: proposal)
    case .interactive, .group, .scope, .boundary: return measure(store.children(of: id)![0], proposal: proposal)
    case .scroll, .list, .variableList, .color, .spacer: return proposal
    case .empty: return .zero
    case .overlay, .tuple:
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

  private func editorTextLayout(
    _ id: NodeID, editor: TextEditor, text: String, width: Float, context: BlockContext
  ) -> TextLayout {
    retainedTextLayout(id, text: text, columns: editor.columns(width: width, context: context))
  }

  private func retainedTextLayout(_ id: NodeID, text: String, columns: Int?) -> TextLayout {
    if let layout = store.withValue(
      for: id,
      { node in
        node.textLayouts.first { $0.columns == columns && $0.layout.text == text }?.layout
      })
    {
      return layout
    }
    let layout = TextLayout(text, columns: columns)
    textLayoutBuilds += 1
    store.modify(id) {
      $0.textLayouts.append((columns, layout))
      if $0.textLayouts.count > 2 { $0.textLayouts.removeFirst() }
    }
    return layout
  }

  private func trailingSizes(_ id: NodeID, spacing: Float, proposal: Size) -> (Size, Size) {
    let children = store.children(of: id)!
    let controls = measure(children[1], proposal: proposal)
    let input = measure(children[0], proposal: Size(width: max(0, proposal.width - controls.width - spacing), height: proposal.height))
    return (input, controls)
  }

  private func expands(_ id: NodeID, axis: StackLayout.Axis) -> Bool {
    let node = store.value(for: id)!
    for decoration in node.decorations {
      if case .layout(.sizing(let x, let y)) = decoration { return (axis == .horizontal ? x : y) == .grow }
    }
    switch node.content {
    case .scroll, .color, .spacer, .list, .variableList: return true
    case .editor, .marquee: return axis == .horizontal
    case .stack, .overlay, .tuple: return store.children(of: id)!.contains { expands($0, axis: axis) }
    case .trailing: return axis == .horizontal
    case .element(let element): return axis == .horizontal ? element.expandsHorizontally : element.expandsVertically
    case .background: return expands(store.children(of: id)![1], axis: axis)
    case .interactive, .group, .scope, .boundary: return expands(store.children(of: id)![0], axis: axis)
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
        let layout = retainedTextLayout(id, text: text.content, columns: columns)
        node.textLayouts = store.value(for: id)!.textLayouts
        node.lines = layout.lines.map(\.text)
        node.selectionLayout = PlainTextLayout(
          text: text.content, rect: rect, cellWidth: cell,
          lineHeight: node.context.fontMetrics.lineAdvance * text.scale * node.context.textScale,
          scale: text.scale * node.context.textScale, columns: columns, retainedLayout: layout)
        node.lineMetrics = node.context.fontMetrics
      }
      node.selectionLayout?.rect = rect
    case .editor(let editor):
      let layout = editorTextLayout(
        id, editor: editor, text: node.editorText, width: rect.size.width, context: node.context)
      node.editorLayout = TextEditorLayout(editor: editor, layout: layout, rect: rect, context: node.context)
      node.textLayouts = store.value(for: id)!.textLayouts
    case .scroll(let scroll):
      let child = store.children(of: id)![0]
      node.contentSize = measure(child, proposal: Size(width: rect.size.width, height: .greatestFiniteMagnitude))
      scroll.controller?.restore(id: node.context.widgetID, interaction: node.context.interaction)
      node.scrollOffset = node.context.interaction.resolveScroll(
        id: node.context.widgetID, viewport: rect, contentSize: node.contentSize,
        controller: scroll.controller, sticksToBottom: scroll.sticksToBottom, horizontal: true)
      try place(child, in: Rect(x: rect.minX - node.scrollOffset.x, y: rect.minY - node.scrollOffset.y, width: node.contentSize.width, height: node.contentSize.height))
    case .element: break
    case .trailing(let spacing):
      let children = store.children(of: id)!
      let sizes = trailingSizes(id, spacing: spacing, proposal: rect.size)
      try place(children[0], in: Rect(x: rect.minX, y: rect.maxY - sizes.0.height, width: sizes.0.width, height: sizes.0.height))
      try place(children[1], in: Rect(x: rect.maxX - sizes.1.width, y: rect.maxY - sizes.1.height, width: sizes.1.width, height: sizes.1.height))
    case .background:
      for child in store.children(of: id)! { try place(child, in: rect) }
    case .interactive, .group, .scope, .boundary: try place(store.children(of: id)![0], in: rect)
    case .list(let list):
      let offset = node.context.interaction.resolveScroll(
        id: node.context.widgetID, viewport: rect,
        contentSize: Size(width: rect.size.width, height: Float(list.count) * list.rowHeight),
        controller: nil, sticksToBottom: false
      ).y
      let range = list.visibleRange(offset: offset, height: rect.size.height)
      let indices = retainedRows(id, visible: range, index: list.index)
      if indices != node.rowIndices || node.rowsDirty {
        var tracked: [TrackedDescription] = []
        var committed = false
        defer { if !committed { for row in tracked { row.subscription.cancel() } } }
        for index in indices {
          tracked.append(try track({ list.row(index) }, context: node.context.scoped([.key(list.key(index))])))
        }
        reconcile(tracked.map(\.description), of: id, updatingRows: true)
        for ((index, child), row) in zip(zip(indices, store.children(of: id)!), tracked) {
          boundaries[BoundaryID(node: child, isPanel: false)]?.subscription.cancel()
          boundaries[BoundaryID(node: child, isPanel: false)] = Boundary(
            content: { list.row(index) }, context: node.context.scoped([.key(list.key(index))]),
            subscription: row.subscription)
        }
        releaseRemovedBoundaries()
        committed = true
        node.rowsDirty = false
        node.visibleRange = range
        node.rowIndices = indices
        node.rowKeys = indices.map(list.key)
      }
      node.offset = offset
      for (index, child) in zip(indices, store.children(of: id)!) {
        let rowRect = Rect(
          x: rect.minX, y: rect.minY + Float(index) * list.rowHeight - offset,
          width: rect.size.width, height: list.rowHeight)
        try installPanels(child)
        _ = refreshEditorText(child)
        _ = measure(child, proposal: rowRect.size)
        try place(child, in: rowRect)
      }
    case .variableList(let list):
      let interaction = node.context.interaction
      let scrollID = node.context.widgetID
      list.controller?.restore(id: scrollID, interaction: interaction)
      let previousState = interaction.scrollStates[scrollID]
      let followsBottom = list.sticksToBottom && previousState.map { abs($0.offset.y - $0.limit.y) <= 1 } == true
      let previousHeights = node.heightIndex
      let previousOffset = Double(previousState?.offset.y ?? 0)
      let previousAnchor = previousHeights?.row(at: previousOffset) ?? node.anchorIndex
      let previousAnchorOffset = previousHeights.map { previousOffset - $0.position(of: previousAnchor) } ?? node.anchorOffset
      var heights = node.heightIndex ?? VariableHeightIndex(count: list.count, estimatedHeight: Double(list.estimatedHeight))
      if node.measuredWidth != rect.size.width
        || node.measuredMetrics != node.context.fontMetrics
        || node.measuredTextScale != node.context.textScale
      {
        heights = VariableHeightIndex(count: list.count, estimatedHeight: Double(list.estimatedHeight))
      }
      if list.count > 0, node.heightIndex == nil || node.measuredWidth != rect.size.width
        || node.measuredMetrics != node.context.fontMetrics || node.measuredTextScale != node.context.textScale
      {
        let restored = node.anchorKey.flatMap { list.index($0) } ?? min(previousAnchor, list.count - 1)
        interaction.scrollStates[scrollID, default: Interaction.ScrollState()].offset.y =
          Float(heights.position(of: restored) + previousAnchorOffset)
      }
      if let request = list.controller?.request, case .row(let key) = request, let index = list.index(key) {
        list.controller?.scroll(to: Float(heights.position(of: index)))
      }
      var offset = Double(interaction.resolveScroll(
        id: node.context.widgetID, viewport: rect,
        contentSize: Size(width: rect.size.width, height: Float(heights.totalHeight)),
        controller: list.controller, sticksToBottom: list.sticksToBottom).y)
      let anchor = heights.row(at: offset)
      let anchorOffset = offset - heights.position(of: anchor)
      var range = heights.visibleRange(offset: offset, height: Double(rect.size.height), overscan: list.overscan)
      var indices = retainedRows(id, visible: range, index: list.index)
      var builtIndices = node.rowIndices
      var dirty = node.rowsDirty
      while true {
        if indices != builtIndices || dirty {
          var tracked: [TrackedDescription] = []
          var committed = false
          defer { if !committed { for row in tracked { row.subscription.cancel() } } }
          for index in indices {
            tracked.append(try track({ list.row(index) }, context: node.context.scoped([.key(list.key(index))])))
          }
          reconcile(tracked.map(\.description), of: id, updatingRows: true)
          for ((index, child), row) in zip(zip(indices, store.children(of: id)!), tracked) {
            let boundary = BoundaryID(node: child, isPanel: false)
            boundaries[boundary]?.subscription.cancel()
            boundaries[boundary] = Boundary(
              content: { list.row(index) }, context: node.context.scoped([.key(list.key(index))]),
              subscription: row.subscription)
          }
          releaseRemovedBoundaries()
          committed = true
          builtIndices = indices
          dirty = false
        }
        for (index, child) in zip(indices, store.children(of: id)!) {
          try installPanels(child)
          _ = refreshEditorText(child)
          let size = measure(child, proposal: Size(width: rect.size.width, height: .infinity))
          precondition(size.height.isFinite)
          heights.measure(index, height: Double(max(1, size.height)))
        }
        offset = min(
          heights.position(of: anchor) + anchorOffset,
          max(0, heights.totalHeight - Double(rect.size.height)))
        if followsBottom { offset = max(0, heights.totalHeight - Double(rect.size.height)) }
        let next = heights.visibleRange(offset: offset, height: Double(rect.size.height), overscan: list.overscan)
        // Only expand during convergence so newly measured short rows cannot cause oscillation.
        let expanded = min(range.lowerBound, next.lowerBound)..<max(range.upperBound, next.upperBound)
        if expanded == range { break }
        range = expanded
        indices = retainedRows(id, visible: range, index: list.index)
      }
      interaction.scrollStates[node.context.widgetID, default: Interaction.ScrollState()].offset.y = Float(offset)
      node.offset = interaction.resolveScroll(
        id: node.context.widgetID, viewport: rect,
        contentSize: Size(width: rect.size.width, height: Float(heights.totalHeight)),
        controller: list.controller, sticksToBottom: false).y
      node.anchorIndex = heights.row(at: Double(node.offset))
      node.anchorKey = list.count > 0 ? list.key(node.anchorIndex) : nil
      node.anchorOffset = Double(node.offset) - heights.position(of: node.anchorIndex)
      interaction.updateScrollLayout(
        id: scrollID, layout: Interaction.ScrollLayout(
          width: rect.size.width, spacing: 0, rows: .indexed(Interaction.IndexedScrollRows(heights: heights, index: list.index))))
      node.heightIndex = heights
      node.measuredWidth = rect.size.width
      node.measuredMetrics = node.context.fontMetrics
      node.measuredTextScale = node.context.textScale
      node.visibleRange = range
      node.rowIndices = indices
      node.rowKeys = indices.map(list.key)
      node.rowsDirty = false
      for (index, child) in zip(indices, store.children(of: id)!) {
        try place(child, in: Rect(
          x: rect.minX, y: rect.minY + Float(heights.position(of: index)) - node.offset,
          width: rect.size.width, height: Float(heights.height(at: index))))
      }
    case .tuple:
      for child in store.children(of: id)! { try place(child, in: rect) }
    case .overlay:
      for child in store.children(of: id)! {
        try place(child, in: Rect(origin: rect.origin, size: measure(child, proposal: rect.size)))
      }
    case .button, .image, .progress, .marquee, .color, .spacer, .empty: break
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

  private func track(_ content: @MainActor () -> any Block, context: BlockContext) throws -> TrackedDescription {
    let subscription = FrameTrackingSubscription(onChange)
    do {
      let description = try withObservationTracking(options: .didSet) {
        subscription.trackCancellation()
        return try lower(content(), context: context)
      } onChange: { [weak subscription] event in
        event.cancel()
        if let callback = subscription?.takeCallback() { ObservationDelivery.enqueue(callback) }
      }
      boundaryBuilds += 1
      return TrackedDescription(description: description, subscription: subscription)
    } catch {
      subscription.cancel()
      throw error
    }
  }

  private func installPanels(_ id: NodeID) throws {
    let node = store.value(for: id)!
    if case .interactive(let interactive) = node.content, node.panelDirty {
      var context = node.context
      context.focusTargets = []
      context.focusLeafClaimed = true
      _ = try installBoundary(id, content: { interactive.nodeContent(node.phase) }, context: context)
    }
    if case .boundary(let boundary) = node.content, node.panelDirty {
      try installBoundary(id, content: boundary.content, context: node.context)
    }
    for child in store.children(of: id)! { try installPanels(child) }
  }

  @discardableResult
  private func installBoundary(_ id: NodeID, content: @escaping @MainActor () -> any Block, context: BlockContext)
    throws -> Bool
  {
    let tracked = try track(content, context: context)
    let changed = reconcile([tracked.description], of: id, updatingRows: true)
    layoutDirty = layoutDirty || changed
    if changed { invalidateMeasurements(from: id) }
    boundaries[BoundaryID(node: id, isPanel: true)]?.subscription.cancel()
    boundaries[BoundaryID(node: id, isPanel: true)] = Boundary(
      content: content, context: context, subscription: tracked.subscription)
    store.modify(id) { $0.panelDirty = false }
    return changed
  }

  @discardableResult
  func refreshEditorText(force: Bool = false) -> Bool {
    guard let root else { return false }
    return refreshEditorText(root, force: force)
  }

  private func refreshEditorText(_ id: NodeID, force: Bool = false) -> Bool {
    let node = store.value(for: id)!
    var changed = false
    if case .editor(let editor) = node.content,
      force || node.editorDirty || editorSubscriptions[id]?.isActive != true
    {
      editorSubscriptions[id]?.cancel()
      let subscription = FrameTrackingSubscription(onChange)
      editorSubscriptions[id] = subscription
      let text = withObservationTracking(options: .didSet) {
        subscription.trackCancellation()
        return editor.getText()
      } onChange: { [weak subscription] event in
        event.cancel()
        if let callback = subscription?.takeCallback() { ObservationDelivery.enqueue(callback) }
      }
      store.modify(id) { $0.editorDirty = false }
      if text != node.editorText {
        store.modify(id) {
          $0.editorText = text
          $0.textLayouts = []
        }
        invalidateMeasurements(from: id)
        layoutDirty = true
        prepared = false
        changed = true
      }
    }
    for child in store.children(of: id)! {
      if refreshEditorText(child, force: force) { changed = true }
    }
    return changed
  }

  func refreshBoundaries() throws {
    let stale = boundaries.keys.filter { boundaries[$0]?.subscription.isActive == false }.sorted {
      let left = depth($0.node)
      let right = depth($1.node)
      return left == right ? !$0.isPanel && $1.isPanel : left < right
    }
    for key in stale {
      let id = key.node
      guard let boundary = boundaries[key], !boundary.subscription.isActive, store.contains(id) else { continue }
      var changed: Bool
      if key.isPanel {
        changed = try installBoundary(id, content: boundary.content, context: boundary.context)
      } else {
        let tracked = try track(boundary.content, context: boundary.context)
        let old = store.value(for: id)!
        changed = !Self.sameLayout(old, tracked.description.node)
        let interactionChanged = !Self.sameInteraction(old, tracked.description.node)
        store.update(id, value: Self.merge(old, tracked.description.node))
        let childrenChanged = reconcile(tracked.description.children, of: id)
        changed = changed || childrenChanged
        layoutDirty = layoutDirty || changed
        boundaries[key] = Boundary(
          content: boundary.content, context: boundary.context, subscription: tracked.subscription)
        if interactionChanged || changed { prepared = false }
      }
      releaseRemovedBoundaries()
      try installPanelsBelow(id)
      if changed { invalidateMeasurements(from: id) }
      refreshBounds(id)
      var parent = store.parent(of: id)
      while let ancestor = parent {
        updateBounds(ancestor)
        parent = store.parent(of: ancestor)
      }
    }
    releaseRemovedBoundaries()
  }

  private func invalidateMeasurements(from id: NodeID) {
    var current: NodeID? = id
    while let node = current {
      store.modify(node) { $0.measurements = [] }
      current = store.parent(of: node)
    }
  }

  private func depth(_ id: NodeID) -> Int {
    var depth = 0
    var parent = store.parent(of: id)
    while let ancestor = parent {
      depth += 1
      parent = store.parent(of: ancestor)
    }
    return depth
  }

  private func installPanelsBelow(_ id: NodeID) throws {
    if case .boundary = store.value(for: id)!.content {
      try installPanels(id)
    } else {
      for child in store.children(of: id)! { try installPanels(child) }
    }
  }

  private func releaseRemovedBoundaries() {
    for id in editorSubscriptions.keys {
      let valid =
        store.contains(id) && store.withValue(for: id) { if case .editor = $0.content { true } else { false } }
      if !valid { editorSubscriptions.removeValue(forKey: id)?.cancel() }
    }
    for key in boundaries.keys {
      let valid =
        store.contains(key.node)
        && (!key.isPanel
          || store.withValue(for: key.node) {
            switch $0.content { case .boundary, .interactive: true; default: false }
          })
      if !valid { boundaries.removeValue(forKey: key)?.subscription.cancel() }
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
    case .editor(let editor):
      bounds = expanded(node.rect, by: max(2, (editor.style ?? node.context.theme.textEditor).borderWidth))
      if let layout = node.editorLayout { bounds = union(bounds, expanded(layout.inner, by: 0)) }
    case .image, .marquee: bounds = expanded(node.rect, by: 2)
    case .progress(let progress):
      bounds = expanded(
        Rect(
          x: node.rect.minX, y: node.rect.minY + (node.rect.size.height - progress.diameter) / 2,
          width: progress.diameter, height: progress.diameter), by: 0)
    case .color: bounds = expanded(node.rect, by: 2)
    case .element(let element): bounds = element.visualBounds(in: node.rect, context: node.context)
    case .empty, .spacer: break
    case .interactive, .background, .scroll, .group, .trailing, .list, .variableList, .stack, .overlay, .tuple, .scope, .boundary:
      for child in store.children(of: id)! { bounds = union(bounds, store.value(for: child)!.visualBounds) }
      switch node.content {
      case .scroll, .list, .variableList: bounds = bounds?.intersection(node.rect) ?? node.rect
      default: break
      }
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
    store.withValue(for: id) { node in prepare(node, id: id) }
  }

  private func prepare(_ node: borrowing Node, id: NodeID) {
    let context = node.context
    let interaction = context.interaction
    var clipCount = 0
    for (decoration, rect) in zip(node.decorations, node.decorationRects) {
      if case .clip = decoration {
        interaction.pushClip(rect)
        clipCount += 1
      }
    }
    defer { for _ in 0..<clipCount { interaction.popClip() } }
    switch node.content {
    case .text(let text) where text.isSelectable:
      if let layout = node.selectionLayout { layout.prepare(text: text, context: context) }
    case .text, .image, .marquee, .color:
      if !context.focusLeafClaimed && !context.navigationIgnored {
        _ = context.buttonState(id: context.widgetID, in: node.rect)
      }
    case .interactive(let interactive):
      _ = context.buttonState(id: interactive.nodeID ?? context.widgetID, in: node.rect, action: interactive.nodeAction)
      prepare(store.children(of: id)![0])
    case .background:
      for child in store.children(of: id)! { prepare(child) }
    case .scroll(let scroll):
      interaction.registerScrollInput(id: context.widgetID, rect: node.rect, horizontal: true)
      interaction.beginGroup(rect: node.rect, scrollID: context.widgetID, navigationID: context.widgetID, navigationName: scroll.name)
      interaction.pushClip(node.rect)
      prepare(store.children(of: id)![0])
      interaction.popClip()
      interaction.endGroup()
    case .element(let element):
      element.prepareInteraction(in: node.rect, context: context)
    case .group(let name):
      interaction.beginGroup(rect: node.rect, navigationID: context.widgetID, navigationName: name)
      prepare(store.children(of: id)![0])
      interaction.endGroup()
    case .trailing:
      interaction.beginGroup(rect: node.rect)
      for child in store.children(of: id)! { prepare(child) }
      interaction.endGroup()
    case .editor(let editor):
      let text = node.editorText
      node.editorLayout?.prepare(editor: editor, context: context, text: { text })
    case .button(let button):
      _ = context.buttonState(
        id: button.id ?? context.widgetID, in: node.rect, role: button.role, action: button.action)
    case .scope(let scope): scope.prepare(in: node.rect, context: context) { prepare(store.children(of: id)![0]) }
    case .boundary: prepare(store.children(of: id)![0])
    case .tuple: for child in store.children(of: id)! { prepare(child) }
    case .list, .variableList:
      interaction.registerScrollInput(id: context.widgetID, rect: node.rect)
      if case .variableList(let list) = node.content, let selection = list.selection {
        let heights = node.heightIndex
        interaction.registerLogicalSelection(
          scrollID: context.widgetID, selectedKey: selection.selectedKey, select: selection.select,
          move: selection.move, reveal: { key in
            guard let index = list.index(key), let heights else { return }
            interaction.scrollStates[context.widgetID, default: Interaction.ScrollState()].offset.y = Float(heights.position(of: index))
          })
      }
      interaction.beginGroup(rect: node.rect, axis: .vertical, scrollID: context.widgetID, navigationID: context.widgetID)
      interaction.pushClip(node.rect)
      for (index, child) in zip(node.rowIndices, store.children(of: id)!) {
        prepare(child)
        if case .variableList(let list) = node.content {
          recordRowLeaves(child, scrollID: context.widgetID, key: list.key(index))
        }
      }
      interaction.popClip()
      interaction.endGroup()
    case .empty, .spacer, .progress: break
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

  private func retainedRows(
    _ id: NodeID, visible: Range<Int>, index: (StructuralKey) -> Int?
  ) -> [Int] {
    let node = store.value(for: id)!
    let interaction = node.context.interaction
    let active = [interaction.editingLeaf, interaction.pressedLeaf].compactMap { $0 }
    guard !active.isEmpty else { return Array(visible) }
    var indices = Set(visible)
    for (key, child) in zip(node.rowKeys, store.children(of: id)!) {
      guard containsLeaf(child, ids: active) else { continue }
      if let retained = index(key) { indices.insert(retained) }
    }
    return indices.sorted()
  }

  private func containsLeaf(_ id: NodeID, ids: [WidgetID]) -> Bool {
    let node = store.value(for: id)!
    if ids.contains(node.context.widgetID) { return true }
    if case .text(let text) = node.content, let id = text.selectionID, ids.contains(id) { return true }
    if case .interactive(let interactive) = node.content, let id = interactive.nodeID, ids.contains(id) { return true }
    if case .button(let button) = node.content, let id = button.id, ids.contains(id) { return true }
    return store.children(of: id)!.contains { containsLeaf($0, ids: ids) }
  }

  private func recordRowLeaves(_ id: NodeID, scrollID: WidgetID, key: StructuralKey) {
    let node = store.value(for: id)!
    let interaction = node.context.interaction
    interaction.recordScrollRow(id: scrollID, leafID: node.context.widgetID, rowKey: key, rect: node.rect)
    if case .text(let text) = node.content, let id = text.selectionID {
      interaction.recordScrollRow(id: scrollID, leafID: id, rowKey: key, rect: node.rect)
    }
    if case .interactive(let interactive) = node.content, let id = interactive.nodeID {
      interaction.recordScrollRow(id: scrollID, leafID: id, rowKey: key, rect: node.rect)
    }
    if case .button(let button) = node.content, let id = button.id {
      interaction.recordScrollRow(id: scrollID, leafID: id, rowKey: key, rect: node.rect)
    }
    for child in store.children(of: id)! { recordRowLeaves(child, scrollID: scrollID, key: key) }
  }

  func refreshInteractiveContent() throws {
    guard let root else { return }
    try refreshInteractiveContent(root)
    if layoutDirty, let layoutRect { try layout(in: layoutRect) }
    prepareIfNeeded()
  }

  private func refreshInteractiveContent(_ id: NodeID) throws {
    let node = store.value(for: id)!
    if case .interactive(let interactive) = node.content {
      let interaction = node.context.interaction
      let leaf = interactive.nodeID ?? node.context.widgetID
      let state = interaction.untrackedLeafState
      let phase: InteractionPhase = state.pressed == leaf && interaction.input.pointerDown
        ? .pressed : state.hovered == leaf || state.selected == leaf ? .hovered : .idle
      if phase != node.phase {
        var context = node.context
        context.focusTargets = []
        context.focusLeafClaimed = true
        _ = try installBoundary(id, content: { interactive.nodeContent(phase) }, context: context)
        store.modify(id) { $0.phase = phase }
        prepared = false
      }
    }
    for child in store.children(of: id)! { try refreshInteractiveContent(child) }
  }

  func dispatch(_ input: InputState) throws {
    if refreshEditorText(force: true), let layoutRect { try layout(in: layoutRect) }
    prepareIfNeeded()
    processInput(input)
    if refreshEditorText(force: true), let layoutRect { try layout(in: layoutRect) }
    try refreshScroll()
    try refreshInteractiveContent()
    prepareIfNeeded()
  }

  func processInput(_ input: InputState) {
    precondition(prepared, "Interaction preparation must precede input")
    guard let root, let node = store.value(for: root) else { return }
    node.context.interaction.processInput(input)
    node.context.interaction.finishInput()
    node.context.interaction.caretClock.setActive(
      node.context.interaction.editingLeaf != nil && node.context.interaction.textSelectionRange == nil,
      timestamp: node.context.interaction.animationFrame.timestamp)
  }

  func refreshScroll() throws {
    guard let root, scrollChanged(root) || hasPendingScrollRequest else { return }
    prepared = false
    try place(root, in: layoutRect!)
  }

  var hasPendingScrollRequest: Bool {
    guard let root else { return false }
    return hasPendingScrollRequest(root)
  }

  private func hasPendingScrollRequest(_ id: NodeID) -> Bool {
    let node = store.value(for: id)!
    switch node.content {
    case .scroll(let scroll): if scroll.controller?.request != nil { return true }
    case .variableList(let list): if list.controller?.request != nil { return true }
    default: break
    }
    return store.children(of: id)!.contains { hasPendingScrollRequest($0) }
  }

  var hasPendingFocus: Bool {
    guard let root else { return false }
    return hasPendingFocus(root)
  }

  private func hasPendingFocus(_ id: NodeID) -> Bool {
    store.withValue(for: id) { $0.context.focusTargets.contains { $0.pendingEditing != nil } }
      || store.children(of: id)!.contains { hasPendingFocus($0) }
  }

  func prepareIfNeeded(viewport: Size? = nil) {
    guard !prepared || hasPendingFocus, let root, let node = store.value(for: root) else { return }
    prepare(viewport: viewport ?? node.context.interaction.viewport.size)
  }

  private func scrollChanged(_ id: NodeID) -> Bool {
    let node = store.value(for: id)!
    switch node.content {
    case .scroll:
      if node.context.interaction.scrollStates[node.context.widgetID]?.offset != node.scrollOffset { return true }
    case .list, .variableList:
      if node.context.interaction.scrollStates[node.context.widgetID]?.offset.y != node.offset { return true }
    default: break
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
    store.withValue(for: id) { node in
      paint(node, id: id, into: &list, clip: clip, cullingEnabled: cullingEnabled)
    }
  }

  private func paint(_ node: borrowing Node, id: NodeID, into list: inout DrawList, clip: Rect, cullingEnabled: Bool) {
    if cullingEnabled, let bounds = node.visualBounds, bounds.intersection(clip) == nil { return }
    paintVisits += 1
    paintDecorations(node, id: id, index: 0, into: &list, clip: clip, cullingEnabled: cullingEnabled)
  }

  private func paintDecorations(
    _ node: borrowing Node, id: NodeID, index: Int, into list: inout DrawList, clip: Rect, cullingEnabled: Bool
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

  private func paintContent(
    _ node: borrowing Node, id: NodeID, into list: inout DrawList, clip: Rect, cullingEnabled: Bool
  ) {
    let context = node.context
    switch node.content {
    case .text(let text) where text.isSelectable:
      node.selectionLayout?.paint(text: text, context: context, into: &list)
    case .text(let text):
      let scale = text.scale * context.textScale
      for (row, line) in node.lines.enumerated() {
        list.text(
          line,
          at: Point(
            x: node.rect.minX,
            y: node.rect.minY + Float(row) * context.fontMetrics.lineAdvance * scale), color: text.color,
          scale: scale)
      }
      paintHighlight(node, into: &list)
    case .image(let image):
      image.draw(into: &list, in: node.rect, context: context)
      paintHighlight(node, into: &list)
    case .progress(let progress):
      progress.draw(into: &list, in: node.rect, context: context)
    case .marquee(let marquee):
      marquee.draw(into: &list, in: node.rect, context: context)
      paintHighlight(node, into: &list)
    case .color(let color):
      list.fillRect(node.rect, color: color)
      paintHighlight(node, into: &list)
    case .editor(let editor):
      node.editorLayout?.paint(editor: editor, context: context, into: &list)
    case .button(let button):
      let interaction = context.interaction
      let id = button.id ?? context.widgetID
      let state = interaction.untrackedLeafState
      button.paint(
        into: &list, in: node.rect, context: context,
        state: ButtonState(
          hovered: state.hovered == id, focused: state.selected == id,
          held: state.pressed == id && interaction.input.pointerDown, clicked: false))
    case .scroll(let scroll):
      list.pushClip(node.rect)
      paint(store.children(of: id)![0], into: &list, clip: clip.intersection(node.rect) ?? .zero, cullingEnabled: cullingEnabled)
      if scroll.showsIndicator {
        scroll.drawIndicator(into: &list, in: node.rect, extent: node.contentSize.height, offset: node.scrollOffset.y, horizontal: false, style: context.theme.scrollView)
        scroll.drawIndicator(into: &list, in: node.rect, extent: node.contentSize.width, offset: node.scrollOffset.x, horizontal: true, style: context.theme.scrollView)
      }
      list.popClip()
    case .list, .variableList:
      list.pushClip(node.rect)
      let clip = clip.intersection(node.rect) ?? .zero
      for child in store.children(of: id)! { paint(child, into: &list, clip: clip, cullingEnabled: cullingEnabled) }
      list.popClip()
    case .empty, .spacer: break
    case .element(let element):
      element.paint(into: &list, in: node.rect, context: context)
    case .interactive, .background, .group, .trailing, .stack, .overlay, .tuple, .scope, .boundary:
      for child in store.children(of: id)! { paint(child, into: &list, clip: clip, cullingEnabled: cullingEnabled) }
    }
  }

  private func paintHighlight(_ node: borrowing Node, into list: inout DrawList) {
    let context = node.context
    if !context.focusLeafClaimed && !context.navigationIgnored {
      FocusHighlight.paint(for: context.widgetID, into: &list, in: node.rect, context: context)
    }
  }
}
