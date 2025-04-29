@MainActor
protocol L2ElementWalker {
  var currentHash: Hash { get set }
  mutating func walkText(_ text: String, _ binding: InputHandler?)
  mutating func beforeGroup(_ group: [any Block])
  mutating func afterGroup(ourHash: Hash, _ group: [any Block])
  mutating func beforeChild() -> Bool
  ///
  /// - Returns: true to break out of the child_loop
  mutating func afterChild(nextChildHash: Hash, prevChildHash: Hash, index: Int, childCount: Int) -> Bool
}
