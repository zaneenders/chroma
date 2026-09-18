public struct ForEach<Data: RandomAccessCollection>: Block, KeyedBlockCollection {
  let keyedContent: TupleBlock

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
    keyedContent = TupleBlock(
      children: data.map { element in
        let key = element[keyPath: id]
        precondition(keys.insert(key).inserted, "Duplicate collection element ID: \(key)")
        return ScopedBlock(content: content(element), path: [.key(StructuralKey(key))])
      })
  }

  public var body: TupleBlock { keyedContent }
}
