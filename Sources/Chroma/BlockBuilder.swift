@resultBuilder
public enum BlockBuilder {
  public static func buildBlock(_ components: (any Block)...) -> TupleBlock {
    TupleBlock(
      children: components.enumerated().flatMap { index, component in
        scopedChildren(component, prefix: [.slot(index)])
      })
  }

  static func flattenedChildren(_ components: [any Block]) -> [any Block] {
    components.flatMap { scopedChildren($0, prefix: []) }
  }

  private static func scopedChildren(
    _ component: any Block, prefix: [StructuralPath.Segment]
  ) -> [any Block] {
    if let scoped = component as? ScopedBlock {
      return scopedChildren(scoped.content, prefix: prefix + scoped.path)
    }
    if let tuple = component as? TupleBlock {
      return tuple.scopedChildren.enumerated().flatMap { index, child in
        scopedChildren(child, prefix: prefix + (child is ScopedBlock ? [] : [.slot(index)]))
      }
    }
    return [ScopedBlock(content: component, path: prefix)]
  }

  public static func buildOptional(_ component: TupleBlock?) -> TupleBlock {
    TupleBlock(children: component.map { scopedChildren($0, prefix: [.branch(0)]) } ?? [])
  }

  public static func buildEither(first component: TupleBlock) -> TupleBlock {
    TupleBlock(children: scopedChildren(component, prefix: [.branch(0)]))
  }

  public static func buildEither(second component: TupleBlock) -> TupleBlock {
    TupleBlock(children: scopedChildren(component, prefix: [.branch(1)]))
  }

  public static func buildArray(_ components: [TupleBlock]) -> TupleBlock {
    TupleBlock(
      children: components.enumerated().flatMap { index, component in
        scopedChildren(component, prefix: [.slot(index)])
      })
  }
}
