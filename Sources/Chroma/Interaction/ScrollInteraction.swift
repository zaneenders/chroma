@MainActor
extension Interaction {
  func scrollDelta(in rect: Rect, horizontal: Bool = false) -> Point {
    guard clippedRect(rect).contains(input.pointerPosition) else { return .zero }
    return Point(x: horizontal ? input.scrollDelta.x : 0, y: input.scrollDelta.y)
  }

  func registerScrollInput(id: WidgetID, rect: Rect, horizontal: Bool = false) {
    let rect = clippedRect(rect)
    building.inputHandlers[id] = { [weak self] in
      guard let self else { return }
      let delta = self.scrollDelta(in: rect, horizontal: horizontal)
      var state = self.scrollStates[id, default: ScrollState()]
      state.offset.x -= delta.x
      state.offset.y -= delta.y
      state.clampOffset()
      self.scrollStates[id] = state
    }
  }

  func recordScrollRow(id: WidgetID, leafID: WidgetID, rowKey: StructuralKey, rect: Rect) {
    scrollStates[id, default: ScrollState()].rows[leafID] = rect
    scrollStates[id, default: ScrollState()].rowKeys[leafID] = rowKey
  }
}
