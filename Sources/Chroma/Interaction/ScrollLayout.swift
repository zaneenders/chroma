@MainActor
extension Interaction {
  func resolveScroll(
    id: WidgetID, viewport: Rect, contentSize: Size, controller: ScrollViewController?,
    sticksToBottom: Bool, horizontal: Bool = false
  ) -> Point {
    let limit = Point(
      x: horizontal ? max(0, contentSize.width - viewport.size.width) : 0,
      y: max(0, contentSize.height - viewport.size.height))
    let previousLimit = scrollLimit(for: id)
    var offset = Point(
      x: min(horizontalScrollOffset(for: id), limit.x), y: min(scrollOffset(for: id), limit.y))
    let wasAtBottom = abs(offset.y - previousLimit) <= 1

    func reveal(_ target: Rect) {
      if target.minY < viewport.minY {
        offset.y -= viewport.minY - target.minY
      } else if target.maxY > viewport.maxY {
        offset.y += target.maxY - viewport.maxY
      }
      if horizontal, target.size.width <= viewport.size.width {
        if target.minX < viewport.minX {
          offset.x -= viewport.minX - target.minX
        } else if target.maxX > viewport.maxX {
          offset.x += target.maxX - viewport.maxX
        }
      }
    }

    let pendingReveal = pendingScrollReveals.removeValue(forKey: id)
    if !refreshingRegistrations, let request = controller?.request {
      if scrollDelta(in: viewport, horizontal: horizontal) != .zero, case .visible = request {
        controller?.request = nil
      } else {
        switch request {
        case .top: offset.y = 0
        case .bottom: offset.y = limit.y
        case .offset(let requested): offset.y = requested
        case .visible(let target): reveal(target)
        case .row(let key):
          if let layout = scrollLayouts[id], let index = layout.rowKeys.firstIndex(of: key) {
            offset.y = layout.rowHeights.prefix(index).reduce(0, +) + Float(index) * layout.spacing
          }
        }
        controller?.request = nil
      }
    } else if sticksToBottom && wasAtBottom && limit.y > previousLimit {
      offset.y = limit.y
    }
    if let pendingReveal { reveal(pendingReveal) }
    offset.x = min(max(0, offset.x), limit.x)
    offset.y = min(max(0, offset.y), limit.y)
    controller?.offset = offset.y
    setScrollOffset(offset.y, for: id)
    setScrollLimit(limit.y, for: id)
    if horizontal {
      controller?.horizontalOffset = offset.x
      setHorizontalScrollOffset(offset.x, for: id)
      setHorizontalScrollLimit(limit.x, for: id)
    }
    return offset
  }
}
