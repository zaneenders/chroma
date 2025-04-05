/// The ``_ArrayBlock`` is the result of a `for <something> in <container>`.
public struct _ArrayBlock<Element: Block>: Block, BlockGroup {
  let _children: [Element]

  init(_ children: [Element]) {
    self._children = children
  }
}

extension _ArrayBlock {
  var children: [any Block] {
    var out: [any Block] = []
    for child in _children {
      out.append(child)
    }
    return out
  }
}
