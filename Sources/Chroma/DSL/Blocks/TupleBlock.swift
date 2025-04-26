/// Composed of N many child ``Block``s.
public struct _TupleBlock<each Component: Block>: Block, TupleBlocks {
  let children: (repeat each Component)

  init(_ child: repeat each Component) {
    self.children = (repeat each child)
  }
}

@MainActor
protocol TupleBlocks<Component> {
  associatedtype Component
  var _children: [any Block] { get }
}

extension _TupleBlock {
  var _children: [any Block] {
    var out: [any Block] = []
    for child in repeat (each children) {
      out.append(child)
    }
    return out
  }
}
