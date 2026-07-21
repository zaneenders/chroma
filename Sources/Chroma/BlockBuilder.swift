/// Builds declarative block bodies, supporting multiple statements, `if`,
/// `if`/`else`, and `for` loops.
@resultBuilder
public enum BlockBuilder {
  public static func buildBlock(_ components: (any Block)...) -> TupleBlock {
    // Control-flow builder methods (`if`, `switch`, and `for`) return a
    // TupleBlock. Flatten those structural tuples here so a surrounding stack
    // receives the branch/loop's actual children instead of one overlaying
    // TupleBlock child.
    TupleBlock(children: components.flatMap(flatten))
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
