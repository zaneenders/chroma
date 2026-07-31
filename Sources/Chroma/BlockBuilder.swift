@resultBuilder
public enum BlockBuilder {
  public static func buildBlock(_ components: (any Block)...) -> TupleBlock {
    TupleBlock(children: flattenedChildren(Array(components)))
  }

  public static func flattenedChildren(_ components: [any Block]) -> [any Block] {
    components.flatMap(flatten)
  }

  private static func flatten(_ component: any Block) -> [any Block] {
    guard let tuple = component as? TupleBlock else { return [component] }
    return tuple.children.flatMap(flatten)
  }

  public static func buildOptional(_ component: TupleBlock?) -> TupleBlock {
    component ?? TupleBlock(children: [])
  }

  public static func buildEither(first component: TupleBlock) -> TupleBlock {
    component
  }

  public static func buildEither(second component: TupleBlock) -> TupleBlock {
    component
  }

  public static func buildArray(_ components: [TupleBlock]) -> TupleBlock {
    TupleBlock(children: components.flatMap(\.children))
  }
}
