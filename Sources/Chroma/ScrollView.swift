public enum ScrollRequest: Equatable, Sendable {
  case top
  case bottom
  case offset(Float)
  case visible(Rect)
}

public final class ScrollViewController {
  fileprivate var request: ScrollRequest?
  fileprivate var lazyStackCache = LazyStackCache()

  public init() {}
  public func scrollToTop() { request = .top }
  public func scrollToBottom() { request = .bottom }
  public func scroll(to offset: Float) { request = .offset(offset) }
  public func scrollToVisible(_ rect: Rect) { request = .visible(rect) }
}

private struct LazyStackCache {
  var width: Float?
  var rowIDs: [WidgetID] = []
  var rowSizes: [Size] = []
}

public struct ScrollView: PrimitiveBlock {
  public var id: WidgetID
  public var showsIndicator: Bool
  public var sticksToBottom: Bool
  public var controller: ScrollViewController?
  public var content: any Block

  public init(
    id: WidgetID,
    showsIndicator: Bool = true,
    sticksToBottom: Bool = false,
    controller: ScrollViewController? = nil,
    @BlockBuilder content: () -> TupleBlock
  ) {
    self.id = id
    self.showsIndicator = showsIndicator
    self.sticksToBottom = sticksToBottom
    self.controller = controller
    self.content = VStack(alignment: .leading, content: content)
  }

  @MainActor public var expandsHorizontally: Bool { true }
  @MainActor public var expandsVertically: Bool { true }

  @MainActor public func sizeThatFits(_ proposal: Size) -> Size { proposal }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    let interaction = Interaction.current
    interaction.registerScrollViewport(rect)
    let contentSize = BlockEngine.measure(
      content,
      proposal: Size(
        width: rect.size.width,
        height: Float.greatestFiniteMagnitude
      )
    )
    let maximumOffset = max(0, contentSize.height - rect.size.height)
    let maximumHorizontalOffset = max(0, contentSize.width - rect.size.width)
    let previousLimit = interaction.scrollLimit(for: id)
    var offset = min(interaction.scrollOffset(for: id), maximumOffset)
    var horizontalOffset = min(
      interaction.horizontalScrollOffset(for: id), maximumHorizontalOffset)
    let wasAtBottom = abs(offset - previousLimit) <= 1

    let pointerIsInside = rect.contains(interaction.input.pointerPosition)
    let isUserScrolling = pointerIsInside
      && (interaction.input.scrollDelta.x != 0 || interaction.input.scrollDelta.y != 0)
    if pointerIsInside {
      offset -= interaction.input.scrollDelta.y
      horizontalOffset -= interaction.input.scrollDelta.x
    }

    for command in interaction.input.commands {
      switch command {
      case .pageUp: offset -= rect.size.height
      case .pageDown: offset += rect.size.height
      case .home: offset = 0
      case .end: offset = maximumOffset
      default: break
      }
    }

    if let request = controller?.request {
      if isUserScrolling, case .visible = request {
        controller?.request = nil
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
          if target.size.width <= rect.size.width {
            if target.minX < rect.minX {
              horizontalOffset -= rect.minX - target.minX
            } else if target.maxX > rect.maxX {
              horizontalOffset += target.maxX - rect.maxX
            }
          }
        }
        controller?.request = nil
      }
    } else if sticksToBottom && wasAtBottom && maximumOffset > previousLimit {
      offset = maximumOffset
    }

    offset = min(max(0, offset), maximumOffset)
    horizontalOffset = min(max(0, horizontalOffset), maximumHorizontalOffset)
    interaction.setScrollOffset(offset, for: id)
    interaction.setHorizontalScrollOffset(horizontalOffset, for: id)
    interaction.setScrollLimit(maximumOffset, for: id)
    interaction.setHorizontalScrollLimit(maximumHorizontalOffset, for: id)

    drawList.pushClip(rect)
    interaction.pushClip(rect)
    BlockEngine.draw(
      content,
      into: &drawList,
      in: Rect(
        x: rect.minX - horizontalOffset, y: rect.minY - offset,
        width: contentSize.width, height: contentSize.height)
    )
    interaction.popClip()

    if showsIndicator && maximumOffset > 0 && rect.size.height > 0 {
      let trackWidth: Float = 3
      let thumbHeight = max(12, rect.size.height * rect.size.height / contentSize.height)
      let travel = rect.size.height - thumbHeight
      let thumbY = rect.minY + travel * (offset / maximumOffset)
      drawList.fillRect(
        Rect(x: rect.maxX - trackWidth, y: thumbY, width: trackWidth, height: thumbHeight),
        color: Color(r: 1, g: 1, b: 1, a: 0.45)
      )
    }
    if showsIndicator && maximumHorizontalOffset > 0 && rect.size.width > 0 {
      let trackHeight: Float = 3
      let thumbWidth = max(12, rect.size.width * rect.size.width / contentSize.width)
      let travel = rect.size.width - thumbWidth
      let thumbX = rect.minX + travel * (horizontalOffset / maximumHorizontalOffset)
      drawList.fillRect(
        Rect(x: thumbX, y: rect.maxY - trackHeight, width: thumbWidth, height: trackHeight),
        color: Color(r: 1, g: 1, b: 1, a: 0.45)
      )
    }
    drawList.popClip()
  }
}

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
  @MainActor public func sizeThatFits(_ proposal: Size) -> Size { proposal }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    let interaction = Interaction.current
    interaction.registerScrollViewport(rect)
    updateCache(width: rect.size.width)

    var contentHeight = controller.lazyStackCache.rowSizes.reduce(0) { $0 + $1.height }
    contentHeight += spacing * Float(max(0, rows.count - 1))
    let maximumOffset = max(0, contentHeight - rect.size.height)
    let previousLimit = interaction.scrollLimit(for: id)
    var offset = min(interaction.scrollOffset(for: id), maximumOffset)
    let wasAtBottom = abs(offset - previousLimit) <= 1

    if rect.contains(interaction.input.pointerPosition) {
      offset -= interaction.input.scrollDelta.y
    }
    for command in interaction.input.commands {
      switch command {
      case .pageUp: offset -= rect.size.height
      case .pageDown: offset += rect.size.height
      case .home: offset = 0
      case .end: offset = maximumOffset
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
            width: rect.size.width, height: height)
        )
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

  @MainActor private func updateCache(width: Float) {
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
        sizes.append(BlockEngine.measure(
          row.content,
          proposal: Size(width: width, height: Float.greatestFiniteMagnitude)
        ))
      }
    }
    controller.lazyStackCache = LazyStackCache(
      width: width, rowIDs: rows.map(\.id), rowSizes: sizes)
  }
}
