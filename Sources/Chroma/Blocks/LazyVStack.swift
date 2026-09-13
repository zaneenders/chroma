public struct LazyVStack: PrimitiveBlock {
  public struct Row {
    public var id: WidgetID
    public var content: any Block {
      didSet { measurementIdentity = LazyRowIdentity() }
    }
    // Copies retain measurements; replacing content or constructing a row invalidates them.
    var measurementIdentity = LazyRowIdentity()

    public init(id: WidgetID, content: any Block) {
      self.id = id
      self.content = content
    }
  }

  public var id: WidgetID
  public var spacing: Float
  public var showsIndicator: Bool
  public var sticksToBottom: Bool
  public var controller: ScrollViewController
  public var rows: [Row]
  private var uniformRows: UniformRows?

  private struct UniformRows {
    let count: Int
    let height: Float
    let content: @MainActor (Int) -> any Block
  }

  public init(
    id: WidgetID,
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

  @MainActor public init<Data: RandomAccessCollection, Content: Block>(
    id: WidgetID,
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

  @MainActor public var expandsHorizontally: Bool { true }
  @MainActor public var expandsVertically: Bool { true }
  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let interaction = context.interaction
    interaction.registerScrollViewport(rect)
    interaction.registerScrollInput(id: id, rect: rect)
    let contentHeight: Float
    if let uniformRows {
      contentHeight =
        Float(uniformRows.count) * uniformRows.height
        + spacing * Float(max(0, uniformRows.count - 1))
    } else {
      updateCache(width: rect.size.width, context: context)
      contentHeight =
        controller.lazyStackCache.rowSizes.reduce(0) { $0 + $1.height }
        + spacing * Float(max(0, rows.count - 1))
    }
    let maximumOffset = max(0, contentHeight - rect.size.height)
    let previousLimit = interaction.scrollLimit(for: id)
    var offset = min(interaction.scrollOffset(for: id), maximumOffset)
    let wasAtBottom = abs(offset - previousLimit) <= 1

    if let request = controller.request {
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
    } else if sticksToBottom && wasAtBottom && maximumOffset > previousLimit {
      offset = maximumOffset
    }

    offset = min(max(0, offset), maximumOffset)
    interaction.setScrollOffset(offset, for: id)
    interaction.setScrollLimit(maximumOffset, for: id)

    drawList.pushClip(rect)
    interaction.pushClip(rect)
    interaction.beginGroup(.vertical, rect: rect)
    let visibleTop = offset
    let visibleBottom = offset + rect.size.height
    if let uniformRows {
      let stride = uniformRows.height + spacing
      let first = Int(
        min(
          Float(uniformRows.count),
          max(
            0,
            ((visibleTop - uniformRows.height) / stride).rounded(.up))))
      let end = Int(
        min(
          Float(uniformRows.count),
          max(
            0,
            (visibleBottom / stride).rounded(.down) + 1)))
      if rect.size.height > 0 && first < end {
        for index in first..<end {
          BlockEngine.draw(
            uniformRows.content(index), into: &drawList,
            in: Rect(
              x: rect.minX, y: rect.minY + Float(index) * stride - offset,
              width: rect.size.width, height: uniformRows.height), context: context)
        }
      }
    } else {
      var y: Float = 0
      for index in rows.indices {
        let height = controller.lazyStackCache.measurements[index].size.height
        let bottom = y + height
        if bottom >= visibleTop && y <= visibleBottom {
          BlockEngine.draw(
            rows[index].content,
            into: &drawList,
            in: Rect(
              x: rect.minX, y: rect.minY + y - offset,
              width: rect.size.width, height: height), context: context)
        }
        y = bottom + spacing
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

  @MainActor private func updateCache(width: Float, context: RenderContext) {
    let cache = controller.lazyStackCache
    let environment = LazyMeasurementEnvironment(
      textScale: context.textScale, fontMetrics: context.fontMetrics, theme: context.theme)
    let sameEnvironment = cache.width == width && cache.environment == environment
    if sameEnvironment && cache.rowIDs.count == rows.count
      && zip(cache.rowIDs, rows).allSatisfy({ $0.0 == $0.1.id })
      && zip(cache.identities, rows).allSatisfy({ $0.0 === $0.1.measurementIdentity })
      && cache.measurements.allSatisfy(\.valid)
    {
      return
    }
    var oldSizes: [WidgetID: (LazyRowIdentity, LazyRowMeasurement)] = [:]
    if sameEnvironment {
      for index in cache.rowIDs.indices {
        let size = cache.measurements[index]
        if size.valid { oldSizes[cache.rowIDs[index]] = (cache.identities[index], size) }
      }
    }

    var sizes: [LazyRowMeasurement] = []
    sizes.reserveCapacity(rows.count)
    for row in rows {
      if let (identity, size) = oldSizes[row.id], identity === row.measurementIdentity {
        sizes.append(size)
      } else {
        sizes.append(
          LazyRowMeasurement {
            BlockEngine.measure(
              row.content,
              proposal: Size(width: width, height: Float.greatestFiniteMagnitude), context: context)
          })
      }
    }
    controller.lazyStackCache = LazyStackCache(
      width: width, environment: environment, rowIDs: rows.map(\.id),
      identities: rows.map(\.measurementIdentity), measurements: sizes)
  }
}
