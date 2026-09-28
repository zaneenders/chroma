public struct ScrollView: PrimitiveBlock {
  public struct Row: Identifiable {
    public let id: AnyHashable
    public var content: any Block {
      didSet { measurementIdentity = LazyRowIdentity() }
    }
    // Copies retain measurements; replacing content or constructing a row invalidates them.
    var measurementIdentity = LazyRowIdentity()
    let key: StructuralKey

    public init(id: some Hashable & Sendable, content: any Block) {
      self.id = AnyHashable(id)
      self.key = StructuralKey(id)
      self.content = content
    }
  }

  private enum Content {
    case block(any Block, ScrollViewController?)
    case rows([Row], ScrollViewController)
    case uniform(UniformRows, ScrollViewController)
  }

  private struct UniformRows {
    let count: Int
    let height: Float
    let keys: [StructuralKey]?
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
      data: data, keys: nil, rowHeight: rowHeight, spacing: spacing,
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
      data: data, keys: data.map { StructuralKey($0.id) }, rowHeight: rowHeight, spacing: spacing,
      showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller, content: content)
    self.name = name
  }

  @MainActor private init<Data: RandomAccessCollection, RowContent: Block>(
    data: Data, keys: [StructuralKey]?, rowHeight: Float, spacing: Float,
    showsIndicator: Bool, sticksToBottom: Bool, controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> RowContent
  ) {
    precondition(rowHeight.isFinite && rowHeight > 0, "rowHeight must be finite and positive")
    precondition(spacing.isFinite && spacing >= 0, "spacing must be finite and nonnegative")
    if let keys { precondition(Set(keys).count == keys.count, "Duplicate lazy collection element ID") }
    self.init(
      spacing: spacing, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom,
      content: .uniform(
        UniformRows(count: data.count, height: rowHeight, keys: keys) { offset in
          content(data[data.index(data.startIndex, offsetBy: offset)])
        }, controller))
  }

  public var focusRule: FocusRule { .container }
  public var expandsHorizontally: Bool { true }
  public var expandsVertically: Bool { true }
  public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    let id = context.widgetID
    let interaction = context.interaction
    controller?.restore(id: id, interaction: interaction)
    let contentSize: Size
    let horizontal: Bool
    switch content {
    case .block(let block, _):
      horizontal = true
      contentSize = BlockEngine.measure(
        block,
        proposal: Size(width: rect.size.width, height: .greatestFiniteMagnitude), context: context)
    case .rows(let rows, let controller):
      horizontal = false
      updateCache(rows: rows, controller: controller, width: rect.size.width, context: context)
      let heights = controller.lazyStackCache.rowSizes.map(\.height)
      interaction.updateScrollLayout(
        id: id,
        layout: Interaction.ScrollLayout(
          width: rect.size.width, spacing: spacing, rowKeys: controller.lazyStackCache.rowKeys, rowHeights: heights))
      contentSize = Size(
        width: rect.size.width,
        height: heights.reduce(0, +) + spacing * Float(max(0, rows.count - 1)))
    case .uniform(let rows, _):
      horizontal = false
      interaction.updateScrollLayout(
        id: id,
        layout: Interaction.ScrollLayout(
          width: rect.size.width, spacing: spacing,
          rowKeys: rows.keys ?? (0..<rows.count).map { StructuralKey($0) },
          rowHeights: Array(repeating: rows.height, count: rows.count)))
      contentSize = Size(
        width: rect.size.width,
        height: Float(rows.count) * rows.height + spacing * Float(max(0, rows.count - 1)))
    }
    interaction.registerScrollInput(id: id, rect: rect, horizontal: horizontal)
    let offsets = interaction.resolveScroll(
      id: id, viewport: rect, contentSize: contentSize, controller: controller,
      sticksToBottom: sticksToBottom, horizontal: horizontal)
    drawList.pushClip(rect)
    interaction.pushClip(rect)
    interaction.beginGroup(
      rect: rect, axis: horizontal ? nil : .vertical,
      scrollID: id, navigationID: id, navigationName: name)
    switch content {
    case .block(let block, _):
      BlockEngine.draw(
        block, into: &drawList,
        in: Rect(
          x: rect.minX - offsets.x, y: rect.minY - offsets.y,
          width: contentSize.width, height: contentSize.height), context: context)
    case .rows, .uniform:
      drawRows(into: &drawList, in: rect, context: context, id: id, offset: offsets.y)
    }
    interaction.endGroup()
    interaction.popClip()
    if showsIndicator {
      drawIndicator(
        into: &drawList, in: rect, extent: contentSize.height, offset: offsets.y,
        horizontal: false, style: context.theme.scrollView)
      if horizontal {
        drawIndicator(
          into: &drawList, in: rect, extent: contentSize.width, offset: offsets.x,
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

  @MainActor private func drawRows(
    into drawList: inout DrawList, in rect: Rect, context: BlockContext, id: WidgetID, offset: Float
  ) {
    let interaction = context.interaction
    let visibleTop = offset
    let visibleBottom = offset + rect.size.height
    let (before, after) = focusBuffer(for: interaction)
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
          drawRow(
            uniformRows.content(index), into: &drawList,
            in: Rect(
              x: rect.minX, y: rect.minY + Float(index) * stride - offset,
              width: rect.size.width, height: uniformRows.height),
            context: uniformRows.keys.map { context.scoped([.key($0[index])]) } ?? context.childScope(index),
            interaction: interaction, offset: offset, scrollID: id,
            rowKey: uniformRows.keys?[index] ?? StructuralKey(index))
        }
      }
    case .rows(let rows, let controller):
      var y: Float = 0
      var visibleFirst: Int?
      var visibleLast: Int?
      for index in rows.indices {
        let height = controller.lazyStackCache.measurements[index].size.height
        let bottom = y + height
        if bottom >= visibleTop && y <= visibleBottom {
          visibleFirst = visibleFirst ?? index
          visibleLast = index
        }
        y = bottom + spacing
      }
      if let visibleFirst, let visibleLast {
        let first = max(0, visibleFirst - before)
        let end = min(rows.count, visibleLast + 1 + after)
        y = 0
        for index in rows.indices {
          let height = controller.lazyStackCache.measurements[index].size.height
          if index >= first && index < end {
            drawRow(
              rows[index].content,
              into: &drawList,
              in: Rect(
                x: rect.minX, y: rect.minY + y - offset,
                width: rect.size.width, height: height),
              context: context.scoped([.key(rows[index].key)]),
              interaction: interaction, offset: offset, scrollID: id, rowKey: rows[index].key)
          }
          y += height + spacing
        }
      }
    }
  }

  /// Rows without controls of their own stay reachable: the row itself becomes a focus leaf, so arrow
  /// keys step through the list and reveal the focused row. Row content is claimed by that leaf —
  /// text inside a row is part of the row's selection rather than a stop of its own, while controls
  /// in the row still register themselves.
  @MainActor private func drawRow(
    _ content: any Block, into drawList: inout DrawList, in rect: Rect,
    context rowContext: BlockContext, interaction: Interaction, offset: Float, scrollID: WidgetID,
    rowKey: StructuralKey
  ) {
    guard let group = interaction.builderStack.last else {
      preconditionFailure("drawRow outside of a frame; call beginFrame first")
    }
    let children = group.children.count
    var rowContext = rowContext
    rowContext.focusLeafClaimed = true
    BlockEngine.draw(content, into: &drawList, in: rect, context: rowContext)
    if group.children.count == children {
      rowContext.focusable(in: rect, into: &drawList)
    }
    recordScrollRows(
      in: group.children[children...], offset: offset, scrollID: scrollID,
      rowKey: rowKey, interaction: interaction)
  }

  /// Logs where the focused leaf of a drawn row sits in the list's content, so a remembered
  /// row can be revealed even after virtualization discards it.
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
      guard leafID == interaction.selectedLeafID else { continue }
      interaction.recordScrollRow(
        id: scrollID, leafID: leafID, rowKey: rowKey,
        rect: Rect(
          x: node.rect.minX, y: node.rect.minY + offset,
          width: node.rect.size.width, height: node.rect.size.height))
    }
  }

  @MainActor private func focusBuffer(for interaction: Interaction) -> (before: Int, after: Int) {
    var before = 0
    var after = 0
    for command in interaction.input.commands {
      guard case .navigation(let navigation) = command else { continue }
      switch navigation {
      case .up: before += 1
      case .down: after += 1
      case .left, .right, .stepIn, .stepOut, .nextFocus, .previousFocus,
        .sectionLeft, .sectionRight, .sectionUp, .sectionDown: break
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
