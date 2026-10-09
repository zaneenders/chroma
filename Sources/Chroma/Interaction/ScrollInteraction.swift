@MainActor
extension Interaction {
  func scrollDelta(in rect: Rect, horizontal: Bool = false) -> Point {
    guard clippedRect(rect).contains(input.pointerPosition) else { return .zero }
    return Point(x: horizontal ? input.scrollDelta.x : 0, y: input.scrollDelta.y)
  }

  func registerScrollInput(
    id: WidgetID, rect: Rect, horizontal: Bool = false, controller: ScrollViewController? = nil
  ) {
    let rect = clippedRect(rect)
    building.inputHandlers[id] = { [weak self, weak controller] in
      guard let self else { return }
      let delta = self.scrollDelta(in: rect, horizontal: horizontal)
      if delta != .zero, case .visible? = controller?.request { controller?.request = nil }
      var state = self.scrollStates[id, default: ScrollState()]
      state.offset.x -= delta.x
      state.offset.y -= delta.y
      state.clampOffset()
      self.scrollStates[id] = state
    }
  }

  func recordScrollRow(id: WidgetID, leafID: WidgetID, rowKey: StructuralKey, rect: Rect) {
    building.scrollRows[id, default: []].insert(leafID)
    scrollStates[id, default: ScrollState()].rows[leafID] = rect
    scrollStates[id, default: ScrollState()].rowKeys[leafID] = rowKey
  }

  /// Keep the current registration and only the offscreen leaves that navigation can restore.
  /// Reconcile first: commands and pending focus still need the preceding registration's metadata.
  func pruneScrollRows() {
    for id in scrollStates.keys {
      guard var state = scrollStates[id] else { continue }
      let visible = building.scrollRows[id, default: []]
      let visibleKeys = Set(visible.compactMap { state.rowKeys[$0] })
      let remembered = rememberedNavigation[id]
      let pending = pendingFocus.flatMap { $0.scrollID == id ? $0.leaf : nil }
      state.rowKeys = state.rowKeys.filter { leaf, key in
        visible.contains(leaf)
          || ((leaf == remembered || leaf == pending) && !visibleKeys.contains(key))
      }
      state.rows = state.rows.filter { state.rowKeys[$0.key] != nil }
      scrollStates[id] = state
    }
    // This is registration-local bookkeeping, not another retained metadata snapshot.
    building.scrollRows = [:]
  }
}
