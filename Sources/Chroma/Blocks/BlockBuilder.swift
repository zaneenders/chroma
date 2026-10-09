@resultBuilder
public enum BlockBuilder {
  public static func buildBlock(_ components: (any Block)...) -> TupleBlock { TupleBlock(children: components) }
  public static func buildOptional(_ component: TupleBlock?) -> TupleBlock {
    var result = component ?? TupleBlock(children: [])
    result.branch = 0
    return result
  }
  public static func buildEither(first component: TupleBlock) -> TupleBlock {
    var result = component
    result.branch = 0
    return result
  }
  public static func buildEither(second component: TupleBlock) -> TupleBlock {
    var result = component
    result.branch = 1
    return result
  }
  public static func buildArray(_ components: [TupleBlock]) -> TupleBlock { TupleBlock(children: components) }
}
