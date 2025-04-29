@MainActor
protocol L2ElementWalker {
  var currentHash: Hash { get set }
  mutating func walkText(_ text: String, _ binding: InputHandler?)
  mutating func beforeGroup(_ group: [any Block])
  mutating func afterGroup(_ group: [any Block])
}
