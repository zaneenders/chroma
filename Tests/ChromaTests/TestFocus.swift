@testable import Chroma

extension Interaction {
  @MainActor func focusFirstControlForTest() {
    guard let tree, let path = tree.firstLeafPath(), let id = tree.node(at: path)?.leafID else { return }
    focus(id)
    for id in scrollStates.keys { scrollStates[id]?.pendingReveal = nil }
  }
}

@MainActor
extension Interaction {
  func scrollState(for key: WidgetID) -> ScrollState {
    if let state = scrollStates[key] { return state }
    let matches = scrollStates.filter { id, _ in
      id.structuralPath?.segments.last(where: {
        if case .key = $0 { return true }
        return false
      }) == .key(StructuralKey(key))
    }
    precondition(matches.count <= 1, "Ambiguous scroll test key")
    return matches.first?.value ?? ScrollState()
  }
}
