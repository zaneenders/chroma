@MainActor
public enum BlockEngine {
  static func resolve(_ block: any Block) -> any PrimitiveBlock {
    if let scoped = block as? ScopedBlock { return resolve(scoped.content) }
    if let primitive = block as? any PrimitiveBlock { return primitive }
    return resolve(block.body)
  }

  static func resolve(
    _ block: any Block, context: RenderContext
  ) -> (primitive: any PrimitiveBlock, context: RenderContext) {
    if let scoped = block as? ScopedBlock {
      return resolve(scoped.content, context: context.scoped(scoped.path))
    }
    let context = context.scoped([.component(ObjectIdentifier(type(of: block)))])
    if let primitive = block as? any PrimitiveBlock { return (primitive, context) }
    return resolve(block.body, context: context)
  }

  static func isSpacer(_ block: any Block) -> Bool {
    if let scoped = block as? ScopedBlock { return isSpacer(scoped.content) }
    return block is Spacer
  }

  public static func measure(
    _ block: any Block,
    proposal: Size,
    context: RenderContext
  ) -> Size {
    let resolved = resolve(block, context: context)
    return resolved.primitive.sizeThatFits(proposal, context: resolved.context)
  }

  public static func draw(
    _ block: any Block,
    into drawList: inout DrawList,
    in rect: Rect,
    context: RenderContext
  ) {
    let resolved = resolve(block, context: context)
    resolved.primitive.draw(into: &drawList, in: rect, context: resolved.context)
  }

  public static func expandsHorizontally(_ block: any Block) -> Bool {
    resolve(block).expandsHorizontally
  }

  public static func expandsVertically(_ block: any Block) -> Bool {
    resolve(block).expandsVertically
  }
}
