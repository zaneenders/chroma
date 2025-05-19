@MainActor
protocol ElementWalker {
  var currentHash: Hash { get set }
  var orientation: Orientation { get set }
  mutating func walkText(_ text: String, _ binding: InputHandler?)
  mutating func beforeGroup(childrenCount: Int)
  mutating func afterGroup(ourHash: Hash)
  mutating func beforeChild() -> Bool
  ///
  /// - Returns: true to break out of the child_loop
  mutating func afterChild(nextChildHash: Hash, prevChildHash: Hash, index: Int, childCount: Int) -> Bool
  mutating func pushNewGroup()
  mutating func popGroup()
}

/// Default
extension ElementWalker {
  mutating func pushNewGroup() {}
  mutating func popGroup() {}
  mutating func beforeGroup(childrenCount: Int) {}
  mutating func afterGroup(ourHash: Hash) {}
  mutating func beforeChild() -> Bool { false }
  mutating func afterChild(
    nextChildHash: Hash,
    prevChildHash: Hash,
    index: Int, childCount: Int
  ) -> Bool { false }
}
