/// ``Text`` ``Block``s are constructed from String literals and not publicly
/// exposed.
struct Text: Block {
  let text: String
  init(_ text: some StringProtocol) {
    self.text = String(text)
  }
}

extension String: Block {
  public var layer: some Block {
    Text(self)
  }
}
