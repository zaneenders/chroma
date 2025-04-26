/// The ``_ArrayBlock`` is the result of a `for <something> in <container>`.
public struct _ArrayBlock<Element: Block>: Block, ArrayBlocks {
  let children: [Element]

  init(_ children: [Element]) {
    self.children = children
  }
}

@MainActor
protocol ArrayBlocks {
  var _children: [any Block] { get }
}

extension _ArrayBlock {
  var _children: [any Block] {
    var out: [any Block] = []
    for child in children {
      out.append(child)
    }
    return out
  }
}
