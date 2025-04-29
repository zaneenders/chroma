@MainActor
protocol L2ElementWalker {
  var currentHash: Hash { get set }
  mutating func walkText(_ text: String, _ binding: InputHandler?)
  mutating func beforeGroup(_ group: [any Block])
  mutating func afterGroup(ourHash: Hash, _ group: [any Block])
  mutating func beforeChild()
  ///
  /// - Returns: true to break out of the child_loop
  mutating func afterChild() -> Bool
}
