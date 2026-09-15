@MainActor
public enum BlockEngine {
  static func resolve(_ block: any Block) -> any PrimitiveBlock {
    if let primitive = block as? any PrimitiveBlock { return primitive }
    return resolve(block.body)
  }

  public static func measure(
    _ block: any Block,
    proposal: Size,
    context: RenderContext
  ) -> Size {
    resolve(block).sizeThatFits(proposal, context: context)
  }

  public static func draw(
    _ block: any Block,
    into drawList: inout DrawList,
    in rect: Rect,
    context: RenderContext
  ) {
    resolve(block).draw(into: &drawList, in: rect, context: context)
  }

  public static func expandsHorizontally(_ block: any Block) -> Bool {
    resolve(block).expandsHorizontally
  }

  public static func expandsVertically(_ block: any Block) -> Bool {
    resolve(block).expandsVertically
  }
}
