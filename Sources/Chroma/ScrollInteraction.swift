@MainActor
extension Interaction {
  func scrollDelta(in rect: Rect, horizontal: Bool = false) -> Point {
    guard clippedRect(rect).contains(input.pointerPosition) else { return .zero }
    return Point(x: horizontal ? input.scrollDelta.x : 0, y: input.scrollDelta.y)
  }

  func registerScrollInput(id: WidgetID, rect: Rect, horizontal: Bool = false) {
    let rect = clippedRect(rect)
    buildingInputHandlers[id] = { [weak self] in
      guard let self else { return }
      let delta = self.scrollDelta(in: rect, horizontal: horizontal)
      let offset = self.scrollOffset(for: id) - delta.y
      let x = self.horizontalScrollOffset(for: id) - delta.x
      self.setScrollOffset(min(offset, self.scrollLimit(for: id)), for: id)
      if horizontal {
        self.setHorizontalScrollOffset(min(x, self.horizontalScrollLimit(for: id)), for: id)
      }
    }
  }

  func scrollOffset(for id: WidgetID) -> Float {
    scrollOffsets[id, default: 0]
  }

  func setScrollOffset(_ offset: Float, for id: WidgetID) {
    scrollOffsets[id] = max(0, offset)
  }

  func horizontalScrollOffset(for id: WidgetID) -> Float {
    horizontalScrollOffsets[id, default: 0]
  }

  func setHorizontalScrollOffset(_ offset: Float, for id: WidgetID) {
    horizontalScrollOffsets[id] = max(0, offset)
  }

  func scrollLimit(for id: WidgetID) -> Float {
    scrollLimits[id, default: 0]
  }

  func setScrollLimit(_ limit: Float, for id: WidgetID) {
    scrollLimits[id] = max(0, limit)
  }

  func horizontalScrollLimit(for id: WidgetID) -> Float {
    horizontalScrollLimits[id, default: 0]
  }

  func setHorizontalScrollLimit(_ limit: Float, for id: WidgetID) {
    horizontalScrollLimits[id] = max(0, limit)
  }

}
