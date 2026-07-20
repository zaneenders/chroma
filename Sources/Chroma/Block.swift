/// A unit of UI, declared SwiftUI-style as a composition of other blocks.
///
/// Blocks are pure value types re-evaluated every frame. Composite blocks
/// implement ``body``; rendering bottoms out at ``PrimitiveBlock`` conformers
/// (`Text`, `Color`, stacks, modifiers), which the ``BlockEngine`` measures
/// and draws into a backend-neutral ``DrawList``.
///
/// ```swift
/// struct Greeting: Block {
///   var body: some Block {
///     Text("Hello")
///       .foregroundColor(.white)
///       .padding(8)
///       .background(Color(r: 0.2, g: 0.2, b: 0.3, a: 1))
///   }
/// }
/// ```
public protocol Block {
  associatedtype Body: Block

  /// The content of the block. Composite blocks return a single expression —
  /// multi-statement composition happens inside stack and builder closures,
  /// which carry `@BlockBuilder`.
  ///
  /// Bodies are evaluated on the main actor, so they may read the ambient
  /// ``Interaction`` context.
  @MainActor var body: Body { get }
}

extension Never: Block {
  public var body: Never { fatalError("Never") }
}

/// A block that draws itself directly instead of composing other blocks.
///
/// This is the escape hatch for custom content: the layout engine assigns a
/// rect, and the block appends draw commands for it. Built-in primitives
/// (`Text`, `Color`, `Spacer`, stacks, modifiers) are implemented the same
/// way.
public protocol PrimitiveBlock: Block where Body == Never {
  /// The size the block wants given the parent's proposal. Greedy blocks
  /// return the proposal; content-hugging blocks (like `Text`) ignore it.
  @MainActor func sizeThatFits(_ proposal: Size) -> Size

  /// Draws the block inside `rect`, the exact region the parent assigned.
  /// Interactive primitives read the ambient ``Interaction`` context here.
  @MainActor func draw(into drawList: inout DrawList, in rect: Rect)

  /// Whether the block grows to fill horizontally proposed space. Stacks
  /// distribute their leftover space among expanding children.
  @MainActor var expandsHorizontally: Bool { get }

  /// Whether the block grows to fill vertically proposed space.
  @MainActor var expandsVertically: Bool { get }
}

extension PrimitiveBlock {
  public var body: Never { fatalError("\(Self.self) is a primitive block") }
  public var expandsHorizontally: Bool { false }
  public var expandsVertically: Bool { false }
}

/// The result of a `@BlockBuilder` closure: an ordered list of blocks.
///
/// Stacks unwrap their builder content into children; a `TupleBlock` standing
/// alone draws its children on top of each other in order.
public struct TupleBlock: PrimitiveBlock {
  public var children: [any Block]

  public init(children: [any Block]) {
    self.children = children
  }

  @MainActor public var expandsHorizontally: Bool {
    children.contains { BlockEngine.expandsHorizontally($0) }
  }

  @MainActor public var expandsVertically: Bool {
    children.contains { BlockEngine.expandsVertically($0) }
  }

  @MainActor public func sizeThatFits(_ proposal: Size) -> Size {
    var result = Size.zero
    for child in children {
      let size = BlockEngine.measure(child, proposal: proposal)
      result.width = max(result.width, size.width)
      result.height = max(result.height, size.height)
    }
    return result
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect) {
    for child in children {
      BlockEngine.draw(child, into: &drawList, in: rect)
    }
  }
}
