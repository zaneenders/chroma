public struct ScrollView: LayoutPreparingBlock {
  public struct Row: Identifiable {
    public let id: AnyHashable
    public var content: any Block {
      didSet { measurementIdentity = LazyRowIdentity() }
    }
    var measurementIdentity = LazyRowIdentity()
    let key: StructuralKey

    public init(id: some Hashable & Sendable, content: any Block) {
      self.id = AnyHashable(id)
      self.key = StructuralKey(id)
      self.content = content
    }

    /// Invalidates persistent measurement after an unobserved value used by this row changes.
    /// Measurements are reused only while row identity, layout environment, and observed
    /// dependencies remain valid. Replacing `content` invalidates automatically; mutations
    /// captured outside Observation require this explicit invalidation. Registration still
    /// resolves current content and callbacks on each update, independently of measurement reuse.
    public mutating func invalidateMeasurement() {
      measurementIdentity = LazyRowIdentity()
    }
  }

  private enum Content {
    case block(any Block, ScrollViewController?)
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
    let content: @MainActor (Int) -> any Block
  }

  private let content: Content
  private let spacing: Float
  public var name: String?
  public var showsIndicator: Bool
  public var sticksToBottom: Bool
  public var controller: ScrollViewController? {
    switch content {
    case .block(_, let controller): controller
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
    controller: ScrollViewController? = nil,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.init(
      name: name, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
      content: .block(VStack(content: content), controller))
  }

  public init(
    _ name: String? = nil, spacing: Float = 0, showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController, rows: [Row]
  ) {
    self.init(
      name: name, spacing: spacing, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
      content: .rows(rows, controller))
  }

  @MainActor public init<Data: RandomAccessCollection, RowContent: Block>(
    _ name: String? = nil, data: Data, rowHeight: Float, spacing: Float = 0,
    showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> RowContent
  ) {
    self.init(
      data: data, keys: nil, selection: nil, rowHeight: rowHeight, spacing: spacing,
      showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller, content: content)
    self.name = name
  }

  @MainActor public init<Data: RandomAccessCollection, RowContent: Block>(
    _ name: String? = nil, data: Data, rowHeight: Float, spacing: Float = 0,
    showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> RowContent
  ) where Data.Element: Identifiable, Data.Element.ID: Sendable {
    self.init(
      data: data, keys: controller.rowIdentity(for: data), selection: nil, rowHeight: rowHeight, spacing: spacing,
      showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller, content: content)
    self.name = name
  }

  @MainActor public init<Data: RandomAccessCollection, RowContent: Block>(
    _ name: String? = nil, data: Data, rowHeight: Float, spacing: Float = 0,
    showsIndicator: Bool = true, sticksToBottom: Bool = false,
    controller: ScrollViewController, selection: ScrollSelection<Data.Element.ID>,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> RowContent
  ) where Data.Element: Identifiable, Data.Element.ID: Sendable {
    let identity = controller.rowIdentity(for: data)
    self.init(
      data: data, keys: identity,
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
      sticksToBottom: sticksToBottom, controller: controller, content: content)
    self.name = name
  }

  @MainActor private init<Data: RandomAccessCollection, RowContent: Block>(
    data: Data, keys: UniformRowIdentity?, selection: LogicalSelection?, rowHeight: Float, spacing: Float,
    showsIndicator: Bool, sticksToBottom: Bool, controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> RowContent
  ) {
    precondition(rowHeight.isFinite && rowHeight > 0, "rowHeight must be finite and positive")
    precondition(spacing.isFinite && spacing >= 0, "spacing must be finite and nonnegative")
    self.init(
      spacing: spacing, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
      content: .uniform(
        UniformRows(count: data.count, height: rowHeight, keys: keys, selection: selection) { offset in
          content(data[data.index(data.startIndex, offsetBy: offset)])
        }, controller))
  }

  private struct ScrollGeometry {
    let id: WidgetID
    let contentSize: Size
    let horizontal: Bool
    let offsets: Point
    let resolvedContent: BlockEngine.Resolved?
  }

  /// Placement events are shared by registration and presentation. No event requires painting.
  private enum Placement {
    case content(BlockEngine.Resolved, Rect)
    case rowFocus(BlockContext, Rect)
  }

  /// The resolved operation owns this snapshot. It is never stored on the controller or
  /// reused by a later update, so painting keeps the exact visible rows and geometry that
  /// registration prepared without measuring, rebuilding rows, or changing scroll state.
  private struct PreparedScroll {
    let rect: Rect
    let geometry: ScrollGeometry
    let placements: [Placement]
  }

  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    var prepared: PreparedScroll?
    return BlockEngine.Resolved(
      expandsHorizontally: { true }, expandsVertically: { true },
      measure: { $0 },
      register: { rect in prepared = registerContent(in: rect, context: context) },
      paint: { list, rect in
        precondition(prepared?.rect == rect, "ScrollView painting requires registration in the same operation")
        paint(prepared!, into: &list, context: context)
      })
  }

  @MainActor private func registerContent(in rect: Rect, context: BlockContext) -> PreparedScroll {
    let geometry = prepareScroll(in: rect, context: context)
    var placements: [Placement] = []
    placeContent(in: rect, context: context, geometry: geometry) { placement in
      placements.append(placement)
      switch placement {
      case .content(let resolved, let rect): resolved.register(in: rect)
      case .rowFocus(let context, let rect): context.registerFocusable(in: rect)
      }
    }
    return PreparedScroll(rect: rect, geometry: geometry, placements: placements)
  }

  @MainActor private func paint(_ prepared: PreparedScroll, into drawList: inout DrawList, context: BlockContext) {
    drawList.pushClip(prepared.rect)
    for placement in prepared.placements {
      switch placement {
      case .content(let resolved, let rect): resolved.paint(into: &drawList, in: rect)
      case .rowFocus(let context, let rect): context.paintFocusHighlight(in: rect, into: &drawList)
      }
    }
    paintIndicators(into: &drawList, in: prepared.rect, geometry: prepared.geometry, context: context)
    drawList.popClip()
  }

  @MainActor private func paintIndicators(
    into drawList: inout DrawList, in rect: Rect, geometry: ScrollGeometry, context: BlockContext
  ) {
    if showsIndicator {
      drawIndicator(
        into: &drawList, in: rect, extent: geometry.contentSize.height, offset: geometry.offsets.y,
        horizontal: false, style: context.theme.scrollView)
      if geometry.horizontal {
        drawIndicator(
          into: &drawList, in: rect, extent: geometry.contentSize.width, offset: geometry.offsets.x,
          horizontal: true, style: context.theme.scrollView)
      }
    }
  }

  @MainActor private func prepareScroll(in rect: Rect, context: BlockContext) -> ScrollGeometry {
    let id = context.widgetID
    let interaction = context.interaction
    controller?.restore(id: id, interaction: interaction)
    let contentSize: Size
    let horizontal: Bool
    var resolvedContent: BlockEngine.Resolved?
    switch content {
    case .block(let block, _):
      horizontal = true
      let resolved = BlockEngine.resolve(block, context: context)
      resolvedContent = resolved
      contentSize = resolved.sizeThatFits(Size(width: rect.size.width, height: .greatestFiniteMagnitude))
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
    interaction.registerScrollInput(id: id, rect: rect, horizontal: horizontal)
    if case .uniform(let rows, let controller) = content, let selection = rows.selection {
      interaction.registerLogicalSelection(
        scrollID: id, selectedKey: selection.selectedKey, select: selection.select,
        move: selection.move, reveal: { controller.scrollToRowKey($0) })
    }
    let offsets = interaction.resolveScroll(
      id: id, viewport: rect, contentSize: contentSize, controller: controller,
      sticksToBottom: sticksToBottom, horizontal: horizontal)
    return ScrollGeometry(
      id: id, contentSize: contentSize, horizontal: horizontal, offsets: offsets,
      resolvedContent: resolvedContent)
  }

  @MainActor private func placeContent(
    in rect: Rect, context: BlockContext, geometry: ScrollGeometry,
    visit: (Placement) -> Void
  ) {
    let interaction = context.interaction
    interaction.pushClip(rect)
    interaction.beginGroup(
      rect: rect, axis: geometry.horizontal ? nil : .vertical,
      scrollID: geometry.id, navigationID: geometry.id, navigationName: name)
    switch content {
    case .block:
      visit(
        .content(
          geometry.resolvedContent!,
          Rect(
            x: rect.minX - geometry.offsets.x, y: rect.minY - geometry.offsets.y,
            width: geometry.contentSize.width, height: geometry.contentSize.height)))
    case .rows, .uniform:
      placeRows(in: rect, context: context, id: geometry.id, offset: geometry.offsets.y, visit: visit)
    }
    interaction.endGroup()
    interaction.popClip()
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

  @MainActor private func placeRows(
    in rect: Rect, context: BlockContext, id: WidgetID, offset: Float,
    visit: (Placement) -> Void
  ) {
    let interaction = context.interaction
    let visibleTop = offset
    let visibleBottom = offset + rect.size.height
    let (before, after) = focusBuffer(for: interaction, keyboardNavigationOverscan: context.keyboardNavigationOverscan)
    switch content {
    case .block: preconditionFailure("Expected virtualized rows")
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
          placeRow(
            uniformRows.content(index),
            in: Rect(
              x: rect.minX, y: rect.minY + Float(index) * stride - offset,
              width: rect.size.width, height: uniformRows.height),
            context: uniformRows.keys.map { context.scoped([.key($0.keys[index])]) } ?? context.childScope(index),
            interaction: interaction, offset: offset, scrollID: id,
            rowKey: uniformRows.keys?.keys[index] ?? StructuralKey(index), visit: visit)
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
          placeRow(
            rows[index].content,
            in: Rect(
              x: rect.minX, y: rect.minY + positions.starts[index] - offset,
              width: rect.size.width, height: positions.heights[index]),
            context: context.scoped([.key(rows[index].key)]),
            interaction: interaction, offset: offset, scrollID: id, rowKey: rows[index].key, visit: visit)
        }
      }
    }
  }

  @MainActor private func placeRow(
    _ content: any Block, in rect: Rect,
    context rowContext: BlockContext, interaction: Interaction, offset: Float, scrollID: WidgetID,
    rowKey: StructuralKey, visit: (Placement) -> Void
  ) {
    guard let group = interaction.builderStack.last else {
      preconditionFailure("placeRow outside of a frame; call beginFrame first")
    }
    let children = group.children.count
    var rowContext = rowContext
    rowContext.focusLeafClaimed = true
    visit(.content(BlockEngine.resolve(content, context: rowContext), rect))
    if group.children.count == children {
      visit(.rowFocus(rowContext, rect))
    }
    recordScrollRows(
      in: group.children[children...], offset: offset, scrollID: scrollID,
      rowKey: rowKey, interaction: interaction)
  }

  @MainActor private func recordScrollRows(
    in nodes: ArraySlice<FocusNode>, offset: Float, scrollID: WidgetID,
    rowKey: StructuralKey, interaction: Interaction
  ) {
    for node in nodes {
      guard case .leaf(let leafID) = node.kind else {
        recordScrollRows(
          in: node.children[...], offset: offset, scrollID: scrollID,
          rowKey: rowKey, interaction: interaction)
        continue
      }
      interaction.recordScrollRow(
        id: scrollID, leafID: leafID, rowKey: rowKey,
        rect: Rect(
          x: node.rect.minX, y: node.rect.minY + offset,
          width: node.rect.size.width, height: node.rect.size.height))
    }
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
    rows: [Row], controller: ScrollViewController, width: Float, context: BlockContext
  ) {
    precondition(Set(rows.map(\.key)).count == rows.count, "Duplicate lazy row ID")
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
            BlockEngine.measure(
              row.content,
              proposal: Size(width: width, height: Float.greatestFiniteMagnitude),
              context: context.scoped([.key(row.key)]))
          })
      }
    }
    controller.lazyStackCache = LazyStackCache(
      structuralPath: context.structuralPath, width: width, environment: environment, rowKeys: rows.map(\.key),
      identities: rows.map(\.measurementIdentity), measurements: sizes)
  }
}
