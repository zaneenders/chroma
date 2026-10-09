@MainActor
extension Interaction {
  func resolveScroll(
    id: WidgetID, viewport: Rect, contentSize: Size, controller: ScrollViewController?,
    sticksToBottom: Bool, horizontal: Bool = false
  ) -> Point {
    let limit = Point(
      x: horizontal ? max(0, contentSize.width - viewport.size.width) : 0,
      y: max(0, contentSize.height - viewport.size.height))
    var state = scrollStates[id, default: ScrollState()]
    let previousLimit = state.limit.y
    var offset = Point(
      x: min(state.offset.x, limit.x), y: min(state.offset.y, limit.y))
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

    let pendingReveal = state.pendingReveal
    state.pendingReveal = nil
    if commitIntent == .presentation, let request = controller?.request {
      var resolved = true
      switch request {
      case .top: offset.y = 0
      case .bottom: offset.y = limit.y
      case .offset(let requested): offset.y = requested
      case .visible(let target): reveal(target)
      case .row(let key):
        guard let layout = scrollStates[id]?.layout,
          let index = layout.index(of: key)
        else {
          resolved = false
          break
        }
        offset.y = layout.position(of: index)
      }
      if resolved { controller?.request = nil }
    } else if sticksToBottom && wasAtBottom && limit.y > previousLimit {
      offset.y = limit.y
    }
    if let pendingReveal { reveal(pendingReveal) }
    state.offset = offset
    state.limit = limit
    state.clampOffset()
    scrollStates[id] = state
    controller?.offset = state.offset.y
    controller?.horizontalOffset = state.offset.x
    return state.offset
  }
}
