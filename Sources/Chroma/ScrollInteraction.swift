@MainActor
extension Interaction {
  public func registerScrollViewport(_ rect: Rect) {
    buildingScrollViewports.append(rect)
  }

  public func scrollOffset(for id: WidgetID) -> Float {
    scrollOffsets[id, default: 0]
  }

  public func setScrollOffset(_ offset: Float, for id: WidgetID) {
    scrollOffsets[id] = max(0, offset)
  }

  public func horizontalScrollOffset(for id: WidgetID) -> Float {
    horizontalScrollOffsets[id, default: 0]
  }

  public func setHorizontalScrollOffset(_ offset: Float, for id: WidgetID) {
    horizontalScrollOffsets[id] = max(0, offset)
  }

  public func scrollLimit(for id: WidgetID) -> Float {
    scrollLimits[id, default: 0]
  }

  public func setScrollLimit(_ limit: Float, for id: WidgetID) {
    scrollLimits[id] = max(0, limit)
  }

  public func horizontalScrollLimit(for id: WidgetID) -> Float {
    horizontalScrollLimits[id, default: 0]
  }

  public func setHorizontalScrollLimit(_ limit: Float, for id: WidgetID) {
    horizontalScrollLimits[id] = max(0, limit)
  }

}
