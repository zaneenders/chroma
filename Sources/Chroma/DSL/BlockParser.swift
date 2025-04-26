/// The parser for the constructed block tree from the user that is parsed and
/// rendered to the screen.
@resultBuilder
@MainActor
public enum BlockParser {
  public static func buildBlock<Component: Block>(
    _ block: Component
  )
    -> Component
  {
    Log.trace("\(block)")
    return block
  }

  public static func buildExpression<Component: Block>(
    _ block: Component
  )
    -> Component
  {
    Log.trace("\(block)")
    return block
  }

  public static func buildBlock<each Component>(
    _ block: repeat each Component
  )
    -> _TupleBlock<repeat each Component>
  where repeat each Component: Block {
    let tuple = _TupleBlock(repeat each block)
    Log.trace("\(tuple)")
    return tuple
  }

  public static func buildEither<B: Block>(
    first block: B
  ) -> B {
    Log.trace("\(block)")
    return block
  }

  public static func buildEither<B: Block>(
    second block: B
  ) -> B {
    Log.trace("\(block)")
    return block
  }

  public static func buildOptional<Component: Block>(
    _ component: Component?
  )
    -> _ArrayBlock<Component>
  {
    let array: _ArrayBlock<Component>
    if let component {
      array = _ArrayBlock<Component>([component])
    } else {
      array = _ArrayBlock<Component>([])
    }
    Log.trace("\(array)")
    return array
  }

  public static func buildArray<Component: Block>(
    _ components: [Component]
  )
    -> _ArrayBlock<Component>
  {
    let array = _ArrayBlock<Component>(components)
    Log.trace("\(array)")
    return array
  }
}
