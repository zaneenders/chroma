@MainActor
protocol L2ElementWalker {
  mutating func walkText(_ text: String, _ binding: InputHandler?)
  mutating func walkGroup(_ group: [L2Element])
}

/*
NOTE: The following names are bad.
- visit
- _walk
*/
extension L2ElementWalker {
  mutating func walk(_ element: L2Element) {
    element.visit(&self)
  }
}

@MainActor
extension L2Element {
  fileprivate func visit(_ walker: inout some L2ElementWalker) {
    self._walk(&walker)
  }
}
