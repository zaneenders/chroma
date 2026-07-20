/// Evaluates blocks into sizes and draw commands.
///
/// Layout is a two-phase, SwiftUI-style negotiation: parents propose a size,
/// children report what they want (``measure(_:proposal:)``), then parents
/// assign exact rects (``draw(_:into:in:)``). Composite blocks recurse
/// through their ``Block/body`` until a ``PrimitiveBlock`` answers.
///
/// Backends call ``draw(_:into:in:)`` once per frame with the viewport rect.
public enum BlockEngine {
  /// The size `block` wants given the parent's proposal.
  public static func measure(_ block: any Block, proposal: Size) -> Size {
    func open<B: Block>(_ block: B) -> Size {
      if let primitive = block as? any PrimitiveBlock {
        return primitive.sizeThatFits(proposal)
      }
      return measure(block.body, proposal: proposal)
    }
    return open(block)
  }

  /// Draws `block` inside `rect`, appending to `drawList`.
  public static func draw(_ block: any Block, into drawList: inout DrawList, in rect: Rect) {
    func open<B: Block>(_ block: B) {
      if let primitive = block as? any PrimitiveBlock {
        primitive.draw(into: &drawList, in: rect)
      } else {
        draw(block.body, into: &drawList, in: rect)
      }
    }
    open(block)
  }

  /// Whether `block` grows to fill horizontally proposed space.
  public static func expandsHorizontally(_ block: any Block) -> Bool {
    func open<B: Block>(_ block: B) -> Bool {
      if let primitive = block as? any PrimitiveBlock {
        return primitive.expandsHorizontally
      }
      return expandsHorizontally(block.body)
    }
    return open(block)
  }

  /// Whether `block` grows to fill vertically proposed space.
  public static func expandsVertically(_ block: any Block) -> Bool {
    func open<B: Block>(_ block: B) -> Bool {
      if let primitive = block as? any PrimitiveBlock {
        return primitive.expandsVertically
      }
      return expandsVertically(block.body)
    }
    return open(block)
  }
}
