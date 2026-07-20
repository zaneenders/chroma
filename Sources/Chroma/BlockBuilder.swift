/// Builds declarative block bodies, supporting multiple statements, `if`,
/// `if`/`else`, and `for` loops.
@resultBuilder
public enum BlockBuilder {
  public static func buildBlock(_ components: (any Block)...) -> TupleBlock {
    TupleBlock(children: components)
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
