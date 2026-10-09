public struct ForEach<Data: RandomAccessCollection>: Block {
  let children: [(StructuralKey, TupleBlock)]

  @MainActor public init(
    _ data: Data,
    @BlockBuilder content: (Data.Element) -> TupleBlock
  ) where Data.Element: Identifiable, Data.Element.ID: Sendable {
    self.init(data, id: \.id, content: content)
  }

  @MainActor public init<ID: Hashable & Sendable>(
    _ data: Data, id: KeyPath<Data.Element, ID>,
    @BlockBuilder content: (Data.Element) -> TupleBlock
  ) {
    var keys = Set<ID>()
    children = data.map { element in
      let key = element[keyPath: id]
      precondition(keys.insert(key).inserted, "Duplicate collection element ID: \(key)")
      return (StructuralKey(key), content(element))
    }
  }

  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let nodes = children.map { key, child in
      buffer.emit(child, context: context.scoped([.key(key)]))
    }
    return buffer.fragment(nodes, context: context)
  }
}
