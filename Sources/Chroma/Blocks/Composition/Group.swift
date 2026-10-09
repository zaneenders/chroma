public struct Group: Block {
  public var name: String?
  public var content: any Block

  public init(_ name: String? = nil, @BlockBuilder content: () -> TupleBlock) {
    self.name = name
    self.content = content()
  }

}
