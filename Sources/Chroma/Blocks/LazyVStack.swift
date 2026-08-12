public struct LazyVStack: PrimitiveBlock {
  public struct Row {
    public var id: WidgetID
    public var content: any Block

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

  @MainActor public var expandsHorizontally: Bool { true }
  @MainActor public var expandsVertically: Bool { true }
  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let interaction = context.interaction
    interaction.registerScrollViewport(rect)
    updateCache(width: rect.size.width, context: context)

    var contentHeight = controller.lazyStackCache.rowSizes.reduce(0) { $0 + $1.height }
    contentHeight += spacing * Float(max(0, rows.count - 1))
    let maximumOffset = max(0, contentHeight - rect.size.height)
    let previousLimit = interaction.scrollLimit(for: id)
    var offset = min(interaction.scrollOffset(for: id), maximumOffset)
    let wasAtBottom = abs(offset - previousLimit) <= 1

    if rect.contains(interaction.input.pointerPosition) {
      offset -= interaction.input.scrollDelta.y
    }
    for command in interaction.input.semanticCommands {
      switch command {
      case .navigation(.pageUp): offset -= rect.size.height
      case .navigation(.pageDown): offset += rect.size.height
      case .navigation(.home): offset = 0
      case .navigation(.end): offset = maximumOffset
      default: break
      }
    }

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
    var y: Float = 0
    for index in rows.indices {
      let height = controller.lazyStackCache.rowSizes[index].height
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
    var oldSizes: [WidgetID: Size] = [:]
    if cache.width == width {
      for (id, size) in zip(cache.rowIDs, cache.rowSizes) {
        oldSizes[id] = size
      }
    }

    var sizes: [Size] = []
    sizes.reserveCapacity(rows.count)
    for row in rows {
      if let size = oldSizes[row.id] {
        sizes.append(size)
      } else {
        sizes.append(
          BlockEngine.measure(
            row.content,
            proposal: Size(width: width, height: Float.greatestFiniteMagnitude), context: context))
      }
    }
    controller.lazyStackCache = LazyStackCache(
      width: width, rowIDs: rows.map(\.id), rowSizes: sizes)
  }
}
