public struct ForEach<Data: RandomAccessCollection>: Block, KeyedBlockCollection
where Data.Element: Identifiable, Data.Element.ID: Sendable {
  let keyedContent: TupleBlock

  @MainActor public init(
    _ data: Data,
    @BlockBuilder content: (Data.Element) -> TupleBlock
  ) {
    var keys = Set<Data.Element.ID>()
    keyedContent = TupleBlock(
      children: data.map { element in
        precondition(keys.insert(element.id).inserted, "Duplicate collection element ID: \(element.id)")
        return ScopedBlock(content: content(element), path: [.key(StructuralKey(element.id))])
      })
  }

  public var body: TupleBlock { keyedContent }
}
