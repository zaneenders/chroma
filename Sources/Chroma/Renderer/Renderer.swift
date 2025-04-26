@MainActor
protocol Renderer: ~Copyable {
  // Mutating to make testing a ``Renderer`` easier.
  mutating func view(_ block: borrowing some Block, with state: BlockState)
}
