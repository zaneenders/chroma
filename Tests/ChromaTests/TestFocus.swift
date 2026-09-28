@testable import Chroma

extension Interaction {
  @MainActor func focusFirstControlForTest() {
    guard let tree, let path = tree.firstLeafPath(), let id = tree.node(at: path)?.leafID else { return }
    focus(id)
    pendingScrollReveals = [:]
  }
}
