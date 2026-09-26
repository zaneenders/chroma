public struct LazyVStack: PrimitiveBlock {
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

  var id: WidgetID?
  public var spacing: Float
  public var showsIndicator: Bool
  public var sticksToBottom: Bool
  public var controller: ScrollViewController
  public var rows: [Row]
  private var uniformRows: UniformRows?

  private struct UniformRows {
    let count: Int
    let height: Float
    var keys: [StructuralKey]? = nil
    let content: @MainActor (Int) -> any Block
  }

  init(
    id: WidgetID?,
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    rows: [Row]
  ) {
    self.id = id
    self.spacing = spacing
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.controller = controller
    self.rows = rows
  }

  public init(
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    rows: [Row]
  ) {
    self.init(
      id: nil, spacing: spacing, showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller,
      rows: rows)
  }

  @MainActor init<Data: RandomAccessCollection, Content: Block>(
    id: WidgetID?,
    data: Data,
    rowHeight: Float,
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) {
    precondition(rowHeight.isFinite && rowHeight > 0, "rowHeight must be finite and positive")
    precondition(spacing.isFinite && spacing >= 0, "spacing must be finite and nonnegative")
    self.init(
      id: id, spacing: spacing, showsIndicator: showsIndicator,
      sticksToBottom: sticksToBottom, controller: controller, rows: [])
    uniformRows = UniformRows(count: data.count, height: rowHeight) { offset in
      content(data[data.index(data.startIndex, offsetBy: offset)])
    }
  }

  @MainActor public init<Data: RandomAccessCollection, Content: Block>(
    data: Data,
    rowHeight: Float,
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) {
    self.init(
      id: nil, data: data, rowHeight: rowHeight, spacing: spacing,
      showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller, content: content)
  }

  @MainActor init<Data: RandomAccessCollection, Content: Block>(
    id: WidgetID?,
    data: Data,
    rowHeight: Float,
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) where Data.Element: Identifiable, Data.Element.ID: Sendable {
    precondition(rowHeight.isFinite && rowHeight > 0, "rowHeight must be finite and positive")
    precondition(spacing.isFinite && spacing >= 0, "spacing must be finite and nonnegative")
    let keys = data.map { StructuralKey($0.id) }
    precondition(Set(keys).count == keys.count, "Duplicate lazy collection element ID")
    self.init(
      id: id, spacing: spacing, showsIndicator: showsIndicator,
      sticksToBottom: sticksToBottom, controller: controller, rows: [])
    uniformRows = UniformRows(count: data.count, height: rowHeight, keys: keys) { offset in
      content(data[data.index(data.startIndex, offsetBy: offset)])
    }
  }

  @MainActor public init<Data: RandomAccessCollection, Content: Block>(
    data: Data,
    rowHeight: Float,
    spacing: Float = 0,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController,
    @BlockBuilder content: @escaping @MainActor (Data.Element) -> Content
  ) where Data.Element: Identifiable, Data.Element.ID: Sendable {
    self.init(
      id: nil, data: data, rowHeight: rowHeight, spacing: spacing,
      showsIndicator: showsIndicator, sticksToBottom: sticksToBottom, controller: controller, content: content)
  }

  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool { true }
  @MainActor public var expandsVertically: Bool { true }
  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let id = id ?? context.widgetID
    let interaction = context.interaction
    interaction.registerScrollInput(id: id, rect: rect)
    let contentHeight: Float
    if let uniformRows {
      contentHeight =
        Float(uniformRows.count) * uniformRows.height
        + spacing * Float(max(0, uniformRows.count - 1))
      let rowKeys = uniformRows.keys ?? (0..<uniformRows.count).map { StructuralKey($0) }
      interaction.updateScrollLayout(
        id: id,
        layout: Interaction.ScrollLayout(
          width: rect.size.width, spacing: spacing, rowKeys: rowKeys,
          rowHeights: Array(repeating: uniformRows.height, count: uniformRows.count)))
    } else {
      updateCache(width: rect.size.width, context: context)
      interaction.updateScrollLayout(
        id: id,
        layout: Interaction.ScrollLayout(
          width: rect.size.width, spacing: spacing,
          rowKeys: controller.lazyStackCache.rowKeys,
          rowHeights: controller.lazyStackCache.rowSizes.map(\.height)))
      contentHeight =
        controller.lazyStackCache.rowSizes.reduce(0) { $0 + $1.height }
        + spacing * Float(max(0, rows.count - 1))
    }
    let maximumOffset = max(0, contentHeight - rect.size.height)
    let previousLimit = interaction.scrollLimit(for: id)
    var offset = min(interaction.scrollOffset(for: id), maximumOffset)
    let wasAtBottom = abs(offset - previousLimit) <= 1

    let reveal = interaction.pendingScrollReveals.removeValue(forKey: id)
    if !interaction.refreshingRegistrations, let request = controller.request {
      if interaction.scrollDelta(in: rect) != .zero, case .visible = request {
        controller.request = nil
      } else {
        switch request {
        case .top: offset = 0
        case .bottom: offset = maximumOffset
        case .offset(let requested): offset = requested
        case .visible(let target):
          if target.minY < rect.minY {
            offset -= rect.minY - target.minY
          } else if target.maxY > rect.maxY {
            offset += target.maxY - rect.maxY
          }
        }
        controller.request = nil
      }
    } else if sticksToBottom && wasAtBottom && maximumOffset > previousLimit {
      offset = maximumOffset
    }
    if let reveal {
      if reveal.minY < rect.minY {
        offset -= rect.minY - reveal.minY
      } else if reveal.maxY > rect.maxY {
        offset += reveal.maxY - rect.maxY
      }
    }

    offset = min(max(0, offset), maximumOffset)
    interaction.setScrollOffset(offset, for: id)
    interaction.setScrollLimit(maximumOffset, for: id)

    drawList.pushClip(rect)
    interaction.pushClip(rect)
    interaction.beginGroup(rect: rect, axis: .vertical, scrollID: id)
    let visibleTop = offset
    let visibleBottom = offset + rect.size.height
    let (before, after) = focusBuffer(for: interaction)
    if let uniformRows {
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
    } else {
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
    interaction.endGroup()
    interaction.popClip()

    if showsIndicator && maximumOffset > 0 && rect.size.height > 0 {
      let trackWidth: Float = 3
      let thumbHeight = max(12, rect.size.height * rect.size.height / contentHeight)
      let travel = rect.size.height - thumbHeight
      let thumbY = rect.minY + travel * (offset / maximumOffset)
      drawList.fillRect(
        Rect(x: rect.maxX - trackWidth, y: thumbY, width: trackWidth, height: thumbHeight),
        color: Color(r: 1, g: 1, b: 1, a: 0.45)
      )
    }
    drawList.popClip()
  }

  /// Rows without controls of their own stay reachable: the row itself becomes a focus leaf, so arrow
  /// keys step through the list and reveal the focused row. Row content is claimed by that leaf —
  /// text inside a row is part of the row's selection rather than a stop of its own, while controls
  /// in the row still register themselves.
  @MainActor private func drawRow(
    _ content: any Block, into drawList: inout DrawList, in rect: Rect,
    context rowContext: RenderContext, interaction: Interaction, offset: Float, scrollID: WidgetID,
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
      case .left, .right, .stepIn, .stepOut: break
      }
    }
    return (before, after)
  }

  @MainActor private func updateCache(width: Float, context: RenderContext) {
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
