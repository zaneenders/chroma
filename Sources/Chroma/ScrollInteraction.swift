@MainActor
extension Interaction {
  /// Input uses geometry from the last completed frame. Layout only normalizes
  /// the resulting offset against the current content extent.
  func registerScrollInput(id: WidgetID, rect: Rect, horizontal: Bool = false) {
    buildingInputHandlers[id] = { [weak self] in
      guard let self else { return }
      var offset = self.scrollOffset(for: id)
      var x = self.horizontalScrollOffset(for: id)
      if rect.contains(self.input.pointerPosition) {
        offset -= self.input.scrollDelta.y
        if horizontal { x -= self.input.scrollDelta.x }
      }
      for command in self.input.commands {
        switch command {
        case .navigation(.pageUp): offset -= rect.size.height
        case .navigation(.pageDown): offset += rect.size.height
        case .navigation(.home): offset = 0
        case .navigation(.end): offset = self.scrollLimit(for: id)
        default: break
        }
      }
      self.setScrollOffset(min(offset, self.scrollLimit(for: id)), for: id)
      if horizontal {
        self.setHorizontalScrollOffset(min(x, self.horizontalScrollLimit(for: id)), for: id)
      }
    }
  }

  func registerScrollViewport(_ rect: Rect) {
    buildingScrollViewports.append(rect)
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
