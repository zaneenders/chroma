public struct ScrollView {
  public typealias RowBuilder<Element> = @MainActor (inout LayoutBuffer, LayoutContext, Element) -> LayoutNode

  public struct Row: Identifiable {
    public let id: AnyHashable
    public var build: LayoutBuilder {
      didSet { measurementIdentity = LazyRowIdentity() }
    }
    var measurementIdentity = LazyRowIdentity()
    let key: StructuralKey

    public init(id: some Hashable & Sendable, build: @escaping LayoutBuilder) {
      self.id = AnyHashable(id)
      self.key = StructuralKey(id)
      self.build = build
    }

    /// Invalidates persistent measurement after an unobserved value used by this row changes.
    /// Measurements are reused only while row identity, layout environment, and observed
    /// dependencies remain valid. Replacing `build` invalidates automatically; mutations
    /// captured outside Observation require this explicit invalidation. Registration still
    /// resolves current content and callbacks on each update, independently of measurement reuse.
    public mutating func invalidateMeasurement() {
      measurementIdentity = LazyRowIdentity()
    }
  }

  private enum Content {
    case layout(LayoutBuilder, ScrollViewController?)
    case rows([Row], ScrollViewController)
    case uniform(UniformRows, ScrollViewController)
  }

  private struct LogicalSelection {
    let selectedKey: @MainActor () -> StructuralKey?
    let select: @MainActor (StructuralKey) -> Void
    let move: @MainActor (Int) -> StructuralKey?
  }

  private struct UniformRows {
    let count: Int
    let height: Float
    let keys: UniformRowIdentity?
    let selection: LogicalSelection?
    let build: RowBuilder<Int>
  }

  private let content: Content
  private let spacing: Float
  public var name: String?
  public var showsIndicator: Bool
  public var sticksToBottom: Bool
  public var controller: ScrollViewController? {
    switch content {
    case .layout(_, let controller): controller
    case .rows(_, let controller), .uniform(_, let controller): controller
    }
  }

  private init(
    name: String? = nil, spacing: Float = 0,
    showsIndicator: Bool, sticksToBottom: Bool, content: Content
  ) {
    self.name = name
    self.spacing = spacing
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.content = content
  }

  public init(
    _ name: String? = nil,
    showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController? = nil, build: @escaping LayoutBuilder
  ) {
    self.init(
      name: name, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
      content: .layout(build, controller))
  }

  public init(
    _ name: String? = nil, spacing: Float = 0, showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController, rows: [Row]
  ) {
    self.init(
      name: name, spacing: spacing, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
      content: .rows(rows, controller))
  }

  @MainActor public init<Data: RandomAccessCollection>(
    _ name: String? = nil, data: Data, rowHeight: Float, spacing: Float = 0,
    showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController, identityRevision: UInt64? = nil,
    build: @escaping RowBuilder<Data.Element>
  ) {
    self.init(
      name: name, data: data, keys: nil, selection: nil, rowHeight: rowHeight, spacing: spacing,
      showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller, build: build)
  }

  /// A supplied revision skips repeated ID scans. Change it whenever IDs or their order change,
  /// including same-count edits. The token is scoped to this controller; row content stays fresh.
  @MainActor public init<Data: RandomAccessCollection>(
    _ name: String? = nil, data: Data, rowHeight: Float, spacing: Float = 0,
    showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController, identityRevision: UInt64? = nil,
    build: @escaping RowBuilder<Data.Element>
  ) where Data.Element: Identifiable, Data.Element.ID: Sendable {
    self.init(
      name: name, data: data, keys: controller.rowIdentity(for: data, identityRevision: identityRevision),
      selection: nil,
      rowHeight: rowHeight, spacing: spacing, showsIndicator: showsIndicator,
      sticksToBottom: sticksToBottom, controller: controller, build: build)
  }

  /// Change identityRevision whenever IDs or their order change. Nil validates IDs on each use.
  @MainActor public init<Data: RandomAccessCollection>(
    _ name: String? = nil, data: Data, rowHeight: Float, spacing: Float = 0,
    showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController, selection: ScrollSelection<Data.Element.ID>, identityRevision: UInt64? = nil,
    build: @escaping RowBuilder<Data.Element>
  ) where Data.Element: Identifiable, Data.Element.ID: Sendable {
    let identity = controller.rowIdentity(for: data, identityRevision: identityRevision)
    self.init(
      name: name, data: data, keys: identity,
      selection: LogicalSelection(
        selectedKey: { selection.selectedID.map { StructuralKey($0) } },
        select: { key in
          if let index = identity.indices[key] { selection.selectedID = identity.ids[index] }
        },
        move: { direction in
          guard let selectedID = selection.selectedID,
            let index = identity.indices[StructuralKey(selectedID)], !identity.ids.isEmpty
          else {
            selection.selectedID = nil
            return nil
          }
          let next = max(0, min(identity.ids.count - 1, index + direction))
          selection.selectedID = identity.ids[next]
          return identity.keys[next]
        }),
      rowHeight: rowHeight, spacing: spacing, showsIndicator: showsIndicator,
      sticksToBottom: sticksToBottom, controller: controller, build: build)
  }

  @MainActor private init<Data: RandomAccessCollection>(
    name: String?, data: Data, keys: UniformRowIdentity?, selection: LogicalSelection?, rowHeight: Float,
    spacing: Float,
    showsIndicator: Bool, sticksToBottom: Bool, controller: ScrollViewController,
    build: @escaping RowBuilder<Data.Element>
  ) {
    precondition(rowHeight.isFinite && rowHeight > 0, "rowHeight must be finite and positive")
    precondition(spacing.isFinite && spacing >= 0, "spacing must be finite and nonnegative")
    self.init(
      name: name, spacing: spacing, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
      content: .uniform(
        UniformRows(count: data.count, height: rowHeight, keys: keys, selection: selection) { buffer, context, offset in
          build(&buffer, context, data[data.index(data.startIndex, offsetBy: offset)])
        }, controller))
  }

  /// Ordered drawing retained by the current operation, after direct registration.
  enum PaintItem {
    case content(LayoutNode, Rect)
    case rowFocus(LayoutContext, Rect)
  }

  /// Never stored on the controller or reused by a later update. Painting consumes
  /// only the registered rows and indicator geometry, without preparing scroll state.
  struct PreparedScroll {
    let rect: Rect
    let contentSize: Size
    let horizontal: Bool
    let offsets: Point
    let items: [PaintItem]
  }

  @MainActor func registerContent(in rect: Rect, context: LayoutContext, buffer: inout LayoutBuffer)
    -> PreparedScroll
  {
    let id = context.widgetID
    let interaction = context.interaction
    controller?.restore(id: id, interaction: interaction)
    let contentSize: Size
    let horizontal: Bool
    var resolvedContent: LayoutNode?
    switch content {
    case .layout(let build, _):
      horizontal = true
      let resolved = build(&buffer, context)
      resolvedContent = resolved
      contentSize = buffer.sizeThatFits(resolved, Size(width: rect.size.width, height: .greatestFiniteMagnitude))
    case .rows(let rows, let controller):
      horizontal = false
      updateCache(rows: rows, controller: controller, width: rect.size.width, context: context)
      var cache = controller.lazyStackCache
      if cache.layout?.spacing != spacing || cache.layout?.width != rect.size.width {
        let heights = cache.measurements.map { $0.size.height }
        cache.layout = Interaction.ScrollLayout(
          width: rect.size.width, spacing: spacing,
          rows: .variable(Interaction.VariableScrollRows(keys: cache.rowKeys, heights: heights, spacing: spacing)))
      }
      controller.lazyStackCache = cache
      let layout = cache.layout!
      interaction.updateScrollLayout(id: id, layout: layout)
      guard case .variable(let positions) = layout.rows else { preconditionFailure("Expected variable rows") }
      contentSize = Size(width: rect.size.width, height: positions.height)
    case .uniform(let rows, _):
      horizontal = false
      interaction.updateScrollLayout(
        id: id,
        layout: Interaction.ScrollLayout(
          width: rect.size.width, spacing: spacing,
          rows: .uniform(count: rows.count, height: rows.height, keys: rows.keys)))
      contentSize = Size(
        width: rect.size.width,
        height: Float(rows.count) * rows.height + spacing * Float(max(0, rows.count - 1)))
    }
    interaction.registerScrollInput(id: id, rect: rect, horizontal: horizontal, controller: controller)
    if case .uniform(let rows, let controller) = content, let selection = rows.selection {
      interaction.registerLogicalSelection(
        scrollID: id, selectedKey: selection.selectedKey, select: selection.select,
        move: selection.move, reveal: { controller.scrollToRowKey($0) })
    }
    let offsets = interaction.resolveScroll(
      id: id, viewport: rect, contentSize: contentSize, controller: controller,
      sticksToBottom: sticksToBottom, horizontal: horizontal)
    var items: [PaintItem] = []
    interaction.pushClip(rect)
    interaction.beginGroup(
      rect: rect, axis: horizontal ? nil : .vertical,
      scrollID: id, navigationID: id, navigationName: name)
    if let resolvedContent {
      let contentRect = Rect(
        x: rect.minX - offsets.x, y: rect.minY - offsets.y,
        width: contentSize.width, height: contentSize.height)
      buffer.register(resolvedContent, in: contentRect)
      items.append(.content(resolvedContent, contentRect))
    } else {
      registerRows(in: rect, context: context, id: id, offset: offsets.y, buffer: &buffer, items: &items)
    }
    interaction.endGroup()
    interaction.popClip()
    return PreparedScroll(rect: rect, contentSize: contentSize, horizontal: horizontal, offsets: offsets, items: items)
  }

  @MainActor func paint(
    _ prepared: PreparedScroll, into drawList: inout DrawList, context: LayoutContext, buffer: inout LayoutBuffer
  ) {
    drawList.pushClip(prepared.rect)
    for item in prepared.items {
      switch item {
      case .content(let resolved, let rect): buffer.paint(resolved, into: &drawList, in: rect)
      case .rowFocus(let context, let rect): context.paintFocusHighlight(in: rect, into: &drawList)
      }
    }
    if showsIndicator {
      drawIndicator(
        into: &drawList, in: prepared.rect, extent: prepared.contentSize.height, offset: prepared.offsets.y,
        horizontal: false, style: context.theme.scrollView)
      if prepared.horizontal {
        drawIndicator(
          into: &drawList, in: prepared.rect, extent: prepared.contentSize.width, offset: prepared.offsets.x,
          horizontal: true, style: context.theme.scrollView)
      }
    }
    drawList.popClip()
  }

  private func drawIndicator(
    into drawList: inout DrawList, in rect: Rect, extent: Float, offset: Float,
    horizontal: Bool, style: ScrollViewStyle
  ) {
    let viewport = horizontal ? rect.size.width : rect.size.height
    let limit = max(0, extent - viewport)
    guard limit > 0, viewport > 0 else { return }
    let length = max(style.minimumThumbLength, viewport * viewport / extent)
    let position = (viewport - length) * offset / limit
    let thumb =
      horizontal
      ? Rect(
        x: rect.minX + position, y: rect.maxY - style.indicatorThickness,
        width: length, height: style.indicatorThickness)
      : Rect(
        x: rect.maxX - style.indicatorThickness, y: rect.minY + position,
        width: style.indicatorThickness, height: length)
    drawList.fillRect(thumb, color: style.indicator)
  }

  @MainActor private func registerRows(
    in rect: Rect, context: LayoutContext, id: WidgetID, offset: Float, buffer: inout LayoutBuffer,
    items: inout [PaintItem]
  ) {
    let interaction = context.interaction
    let visibleTop = offset
    let visibleBottom = offset + rect.size.height
    let (before, after) = focusBuffer(for: interaction, keyboardNavigationOverscan: context.keyboardNavigationOverscan)
    switch content {
    case .layout: preconditionFailure("Expected virtualized rows")
    case .uniform(let uniformRows, _):
      let stride = uniformRows.height + spacing
      let visibleFirst = Int(
        min(
          Float(uniformRows.count),
          max(
            0,
            ((visibleTop - uniformRows.height) / stride).rounded(.up))))
      let visibleEnd = Int(
        min(
          Float(uniformRows.count),
          max(
            0,
            (visibleBottom / stride).rounded(.down) + 1)))
      let first = max(0, visibleFirst - before)
      let end = min(uniformRows.count, visibleEnd + after)
      if rect.size.height > 0 && first < end {
        for index in first..<end {
          registerRow(
            { buffer, context in uniformRows.build(&buffer, context, index) },
            in: Rect(
              x: rect.minX, y: rect.minY + Float(index) * stride - offset,
              width: rect.size.width, height: uniformRows.height),
            context: uniformRows.keys.map { context.scoped([.key($0.keys[index])]) } ?? context.childScope(index),
            interaction: interaction, offset: offset, scrollID: id,
            rowKey: uniformRows.keys?.keys[index] ?? StructuralKey(index), buffer: &buffer, items: &items)
        }
      }
    case .rows(let rows, let controller):
      guard case .variable(let positions) = controller.lazyStackCache.layout?.rows else {
        preconditionFailure("Expected variable rows")
      }
      let first = max(0, positions.firstRow(endingAtOrAfter: visibleTop) - before)
      let end = min(rows.count, positions.firstRow(startingAfter: visibleBottom) + after)
      if rect.size.height > 0 && first < end {
        for index in first..<end {
          registerRow(
            rows[index].build,
            in: Rect(
              x: rect.minX, y: rect.minY + positions.starts[index] - offset,
              width: rect.size.width, height: positions.heights[index]),
            context: context.scoped([.key(rows[index].key)]),
            interaction: interaction, offset: offset, scrollID: id, rowKey: rows[index].key, buffer: &buffer,
            items: &items)
        }
      }
    }
  }

  @MainActor private func registerRow(
    _ build: LayoutBuilder, in rect: Rect,
    context rowContext: LayoutContext, interaction: Interaction, offset: Float, scrollID: WidgetID,
    rowKey: StructuralKey, buffer: inout LayoutBuffer, items: inout [PaintItem]
  ) {
    guard let group = interaction.builderStack.last else {
      preconditionFailure("registerRow outside of a frame; call beginFrame first")
    }
    let children = group.children.count
    var rowContext = rowContext
    rowContext.focusLeafClaimed = true
    let node = build(&buffer, rowContext)
    buffer.register(node, in: rect)
    items.append(.content(node, rect))
    if group.children.count == children {
      rowContext.registerFocusable(in: rect)
      items.append(.rowFocus(rowContext, rect))
    }
    interaction.recordScrollRows(
      in: group, fromChild: children, offset: offset, scrollID: scrollID,
      rowKey: rowKey)
  }

  @MainActor private func focusBuffer(
    for interaction: Interaction, keyboardNavigationOverscan: Bool
  ) -> (before: Int, after: Int) {
    // A raw key's scoped binding is known only after registration. Prepare either
    // adjacent row in this same update rather than registering a second time.
    if keyboardNavigationOverscan { return (1, 1) }
    var before = 0
    var after = 0
    for command in interaction.input.commands {
      guard case .navigation(let navigation) = command else { continue }
      switch navigation {
      case .up: before += 1
      case .down: after += 1
      case .left, .right, .stepIn, .stepOut, .nextFocus, .previousFocus,
        .sectionLeft, .sectionRight, .sectionUp, .sectionDown:
        break
      }
    }
    return (before, after)
  }

  @MainActor private func updateCache(
    rows: [Row], controller: ScrollViewController, width: Float, context: LayoutContext
  ) {
    let cache = controller.lazyStackCache
    let environment = LazyMeasurementEnvironment(
      textScale: context.textScale, fontMetrics: context.fontMetrics, theme: context.theme)
    let sameEnvironment =
      cache.width == width && cache.environment == environment
      && cache.structuralPath == context.structuralPath
    if sameEnvironment && cache.rowKeys.count == rows.count
      && zip(cache.rowKeys, rows).allSatisfy({ $0.0 == $0.1.key })
      && zip(cache.identities, rows).allSatisfy({ $0.0 === $0.1.measurementIdentity })
      && cache.measurements.allSatisfy(\.valid)
    {
      return
    }
    precondition(Set(rows.map(\.key)).count == rows.count, "Duplicate lazy row ID")
    var oldSizes: [StructuralKey: (LazyRowIdentity, LazyRowMeasurement)] = [:]
    if sameEnvironment {
      for index in cache.rowKeys.indices {
        let size = cache.measurements[index]
        if size.valid { oldSizes[cache.rowKeys[index]] = (cache.identities[index], size) }
      }
    }

    var sizes: [LazyRowMeasurement] = []
    sizes.reserveCapacity(rows.count)
    for row in rows {
      if let (identity, size) = oldSizes[row.key], identity === row.measurementIdentity {
        sizes.append(size)
      } else {
        sizes.append(
          LazyRowMeasurement {
            controller.measurementBuffer.reset()
            defer { controller.measurementBuffer.reset() }
            let node = row.build(&controller.measurementBuffer, context.scoped([.key(row.key)]))
            return controller.measurementBuffer.sizeThatFits(
              node, Size(width: width, height: Float.greatestFiniteMagnitude))
          })
      }
    }
    controller.lazyStackCache = LazyStackCache(
      structuralPath: context.structuralPath, width: width, environment: environment, rowKeys: rows.map(\.key),
      identities: rows.map(\.measurementIdentity), measurements: sizes)
  }
}
