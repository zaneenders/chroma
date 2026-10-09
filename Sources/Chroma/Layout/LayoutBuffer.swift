import BasicContainers

/// An operation-local integer handle, not a widget's persistent identity.
/// Resetting its buffer invalidates it, even when the same slot is reused.
public struct LayoutNode: Hashable, Sendable {
  fileprivate let owner: UInt64
  fileprivate let generation: UInt64
  fileprivate let index: Int
}

/// The single execution path for direct construction and Block builders.
/// Storage capacity is reused; callbacks and measurements never survive reset.
/// Noncopyable ownership prevents callbacks from capturing their own buffer.
@MainActor
public struct LayoutBuffer: ~Copyable {
  struct Record {
    enum Kind {
      case primitive(Int)
      case custom(Int)
      case stack(Int)
    }
    let kind: Kind
    var horizontal: Bool?
    var vertical: Bool?
    var measurements = -1
  }
  struct Primitive {
    let block: any PaintableBlock
    let context: BlockContext
  }
  struct Callbacks {
    let expandHorizontal: (inout LayoutBuffer) -> Bool
    let expandVertical: (inout LayoutBuffer) -> Bool
    let measure: (inout LayoutBuffer, Size) -> Size
    let register: (inout LayoutBuffer, Rect) -> Void
    let paint: (inout LayoutBuffer, inout DrawList, Rect) -> Void
  }
  struct Measurement {
    let proposal: Size
    let size: Size
    let next: Int
    var placements: Range<Int>? = nil
  }
  struct Stack {
    let axis: FocusGroupAxis
    let spacing: Float
    let reversed: Bool
    let bottomAligned: Bool
    let children: Range<Int>
    let context: BlockContext
  }
  struct Child {
    let node: LayoutNode
    let spacer: Bool
  }

  private static var nextOwner: UInt64 = 0
  private let owner: UInt64
  private var generation: UInt64 = 0
  private var nodes = BasicContainers.UniqueArray<Record>()
  private var measurements = BasicContainers.UniqueArray<Measurement>()
  private var primitives = BasicContainers.UniqueArray<Primitive>()
  private var callbacks = BasicContainers.UniqueArray<Callbacks>()
  private var stacks = BasicContainers.UniqueArray<Stack>()
  private var children = BasicContainers.UniqueArray<Child>()
  private var placements = BasicContainers.UniqueArray<Rect>()

  public init() {
    Self.nextOwner += 1
    owner = Self.nextOwner
  }

  public var count: Int { nodes.count }
  public var customNodeCount: Int { callbacks.count }
  public var capacity: Int { nodes.capacity }

  /// Releases every captured application value while keeping allocated storage.
  public mutating func reset(releasingCapacity: Bool = false) {
    generation += 1
    nodes.removeAll()
    measurements.removeAll()
    primitives.removeAll()
    callbacks.removeAll()
    stacks.removeAll()
    children.removeAll()
    placements.removeAll()
    if releasingCapacity {
      nodes = .init()
      measurements = .init()
      primitives = .init()
      callbacks = .init()
      stacks = .init()
      children = .init()
      placements = .init()
    }
  }

  public func contains(_ node: LayoutNode) -> Bool {
    node.owner == owner && node.generation == generation && nodes.indices.contains(node.index)
  }

  public mutating func append(
    expandsHorizontally: @escaping (inout LayoutBuffer) -> Bool = { _ in false },
    expandsVertically: @escaping (inout LayoutBuffer) -> Bool = { _ in false },
    measure: @escaping (inout LayoutBuffer, Size) -> Size,
    register: @escaping (inout LayoutBuffer, Rect) -> Void,
    paint: @escaping (inout LayoutBuffer, inout DrawList, Rect) -> Void
  ) -> LayoutNode {
    let node = LayoutNode(owner: owner, generation: generation, index: nodes.count)
    if nodes.count == nodes.capacity { PipelineMetrics.record(.bufferGrowth) }
    PipelineMetrics.record(.layoutNode)
    nodes.append(Record(kind: .custom(callbacks.count)))
    if callbacks.count == callbacks.capacity { PipelineMetrics.record(.bufferGrowth) }
    callbacks.append(
      Callbacks(
        expandHorizontal: expandsHorizontally, expandVertical: expandsVertically,
        measure: measure, register: register, paint: paint))
    return node
  }

  public mutating func append(
    child: LayoutNode,
    register: @escaping (inout LayoutBuffer, Rect) -> Void,
    paint: @escaping (inout LayoutBuffer, inout DrawList, Rect) -> Void
  ) -> LayoutNode {
    append(
      expandsHorizontally: { $0.expandsHorizontally(child) },
      expandsVertically: { $0.expandsVertically(child) },
      measure: { $0.sizeThatFits(child, $1) }, register: register, paint: paint)
  }

  public mutating func prepare(_ block: any Block, context: BlockContext) -> LayoutNode {
    if let scoped = block as? ScopedBlock {
      return prepare(scoped.content, context: context.scoped(scoped.path))
    }
    if let container = block as? any LayoutPreparingBlock {
      let context =
        container.preservesContentIdentity
        ? context : context.scoped([.component(ObjectIdentifier(type(of: block)))])
      return container.prepareLayout(context: context, in: &self)
    }
    if let primitive = block as? any PaintableBlock {
      let context =
        primitive.preservesContentIdentity
        ? context : context.scoped([.component(ObjectIdentifier(type(of: block)))])
      let node = LayoutNode(owner: owner, generation: generation, index: nodes.count)
      if nodes.count == nodes.capacity { PipelineMetrics.record(.bufferGrowth) }
      PipelineMetrics.record(.layoutNode)
      nodes.append(Record(kind: .primitive(primitives.count)))
      if primitives.count == primitives.capacity { PipelineMetrics.record(.bufferGrowth) }
      primitives.append(Primitive(block: primitive, context: context))
      return node
    }
    PipelineMetrics.record(.bodyEvaluation)
    return prepare(block.body, context: context.scoped([.component(ObjectIdentifier(type(of: block)))]))
  }

  public mutating func expandsHorizontally(_ node: LayoutNode) -> Bool { expands(node, horizontally: true) }
  public mutating func expandsVertically(_ node: LayoutNode) -> Bool { expands(node, horizontally: false) }

  private mutating func expands(_ node: LayoutNode, horizontally: Bool) -> Bool {
    precondition(contains(node), "LayoutNode belongs to another operation")
    if let value = horizontally ? nodes[node.index].horizontal : nodes[node.index].vertical { return value }
    let value: Bool
    switch nodes[node.index].kind {
    case .primitive(let index):
      let block = primitives[index].block
      value = horizontally ? block.expandsHorizontally : block.expandsVertically
    case .stack(let index): value = stackExpands(stacks[index], horizontally: horizontally)
    case .custom(let index):
      let callback = horizontally ? callbacks[index].expandHorizontal : callbacks[index].expandVertical
      value = callback(&self)
    }
    precondition(contains(node), "Cannot reset LayoutBuffer from a callback")
    if horizontally { nodes[node.index].horizontal = value } else { nodes[node.index].vertical = value }
    return value
  }

  public mutating func sizeThatFits(_ node: LayoutNode, _ proposal: Size) -> Size {
    precondition(contains(node), "LayoutNode belongs to another operation")
    PipelineMetrics.record(.measurement)
    var index = nodes[node.index].measurements
    while index >= 0 {
      let entry = measurements[index]
      if entry.proposal == proposal {
        PipelineMetrics.record(.measurementCacheHit)
        return entry.size
      }
      index = entry.next
    }
    // Release the storage borrow before recursion, which can append more nodes.
    let size: Size
    var layout: Range<Int>?
    switch nodes[node.index].kind {
    case .primitive(let index):
      let primitive = primitives[index]
      size = primitive.block.sizeThatFits(proposal, context: primitive.context)
    case .stack(let index): (size, layout) = placeStack(stacks[index], proposal: proposal)
    case .custom(let index):
      let callback = callbacks[index].measure
      size = callback(&self, proposal)
    }
    precondition(contains(node), "Cannot reset LayoutBuffer from a callback")
    let next = nodes[node.index].measurements
    nodes[node.index].measurements = measurements.count
    if measurements.count == measurements.capacity { PipelineMetrics.record(.bufferGrowth) }
    measurements.append(Measurement(proposal: proposal, size: size, next: next, placements: layout))
    return size
  }

  public mutating func register(_ node: LayoutNode, in rect: Rect) {
    precondition(contains(node), "LayoutNode belongs to another operation")
    PipelineMetrics.record(.placement)
    PipelineMetrics.record(.registration)
    switch nodes[node.index].kind {
    case .primitive(let index):
      let primitive = primitives[index]
      BlockEngine.registerResolved(primitive.block, in: rect, context: primitive.context)
    case .stack(let index):
      let stack = stacks[index]
      let range = stackPlacements(node, proposal: rect.size)
      stack.context.withFocusGroup(in: rect, axis: stack.axis) {
        for (childIndex, placementIndex) in zip(stack.children, range) {
          let child = children[childIndex].node
          let placement = placed(placements[placementIndex], in: rect)
          register(child, in: placement)
        }
      }
    case .custom(let index):
      let callback = callbacks[index].register
      callback(&self, rect)
    }
    precondition(contains(node), "Cannot reset LayoutBuffer from a callback")
  }

  public mutating func paint(_ node: LayoutNode, into list: inout DrawList, in rect: Rect) {
    precondition(contains(node), "LayoutNode belongs to another operation")
    PipelineMetrics.record(.paint)
    BlockEngine.countDrawingCommands(into: &list) { list in
      switch nodes[node.index].kind {
      case .primitive(let index):
        let primitive = primitives[index]
        BlockEngine.paintResolved(primitive.block, into: &list, in: rect, context: primitive.context)
      case .stack(let index):
        let stack = stacks[index]
        let range = stackPlacements(node, proposal: rect.size)
        for (childIndex, placementIndex) in zip(stack.children, range) {
          let child = children[childIndex].node
          let placement = placed(placements[placementIndex], in: rect)
          paint(child, into: &list, in: placement)
        }
      case .custom(let index):
        let callback = callbacks[index].paint
        callback(&self, &list, rect)
      }
    }
    precondition(contains(node), "Cannot reset LayoutBuffer from a callback")
  }

  mutating func prepareStack(
    _ originals: [any Block], axis: FocusGroupAxis, spacing: Float, reversed: Bool,
    bottomAligned: Bool = false, context: BlockContext
  ) -> LayoutNode {
    let children = originals.enumerated().map { index, child in
      prepare(child, context: context.childContext(for: child, at: index))
    }
    return stack(
      children, spacers: originals.map(BlockEngine.isSpacer), axis: axis, spacing: spacing,
      reversed: reversed, bottomAligned: bottomAligned, context: context)
  }

  /// Direct stack construction. Builders emit these exact same records.
  /// Give each child its own keyed or positional context when preparing it.
  public mutating func stack(
    _ childNodes: [LayoutNode], axis: FocusGroupAxis, spacing: Float = 0,
    reversed: Bool = false, bottomAligned: Bool = false, context: BlockContext
  ) -> LayoutNode {
    stack(
      childNodes,
      spacers: childNodes.map { node in
        precondition(contains(node), "LayoutNode belongs to another operation")
        if case .primitive(let index) = nodes[node.index].kind { return primitives[index].block is Spacer }
        return false
      }, axis: axis, spacing: spacing, reversed: reversed, bottomAligned: bottomAligned, context: context)
  }

  mutating func stack(
    _ childNodes: [LayoutNode], spacers: [Bool], axis: FocusGroupAxis, spacing: Float,
    reversed: Bool, bottomAligned: Bool, context: BlockContext
  ) -> LayoutNode {
    let first = children.count
    for (child, spacer) in zip(childNodes, spacers) {
      precondition(contains(child), "LayoutNode belongs to another operation")
      if children.count == children.capacity { PipelineMetrics.record(.bufferGrowth) }
      children.append(Child(node: child, spacer: spacer))
    }
    let node = LayoutNode(owner: owner, generation: generation, index: nodes.count)
    if nodes.count == nodes.capacity { PipelineMetrics.record(.bufferGrowth) }
    PipelineMetrics.record(.layoutNode)
    nodes.append(Record(kind: .stack(stacks.count)))
    if stacks.count == stacks.capacity { PipelineMetrics.record(.bufferGrowth) }
    stacks.append(
      Stack(
        axis: axis, spacing: spacing, reversed: reversed, bottomAligned: bottomAligned,
        children: first..<children.count, context: context))
    return node
  }

  private mutating func stackExpands(_ stack: Stack, horizontally: Bool) -> Bool {
    for index in stack.children {
      let child = children[index]
      if child.spacer && (stack.axis == .horizontal) != horizontally { continue }
      if horizontally ? expandsHorizontally(child.node) : expandsVertically(child.node) { return true }
    }
    return false
  }

  private mutating func placeStack(_ stack: Stack, proposal: Size) -> (Size, Range<Int>) {
    let main: WritableKeyPath<Size, Float> = stack.axis == .horizontal ? \.width : \.height
    let cross: WritableKeyPath<Size, Float> = stack.axis == .horizontal ? \.height : \.width
    let start = placements.count
    for _ in stack.children {
      if placements.count == placements.capacity { PipelineMetrics.record(.bufferGrowth) }
      placements.append(.zero)
    }
    let range = start..<placements.count
    var fixed: Float = 0
    var expanders = 0
    for (index, placement) in zip(stack.children, range) {
      let child = children[index]
      var size = sizeThatFits(child.node, proposal)
      if child.spacer { size[keyPath: cross] = 0 }
      placements[placement].size = size
      if stack.axis == .horizontal ? expandsHorizontally(child.node) : expandsVertically(child.node) {
        expanders += 1
      } else {
        fixed += size[keyPath: main]
      }
    }
    if expanders > 0 {
      let gaps = stack.spacing * Float(max(0, stack.children.count - 1))
      let share = max(0, proposal[keyPath: main] - fixed - gaps) / Float(expanders)
      var shared = proposal
      shared[keyPath: main] = share
      for (index, placement) in zip(stack.children, range) {
        let child = children[index]
        guard stack.axis == .horizontal ? expandsHorizontally(child.node) : expandsVertically(child.node) else {
          continue
        }
        var size = sizeThatFits(child.node, shared)
        size[keyPath: main] = share
        if child.spacer { size[keyPath: cross] = 0 }
        placements[placement].size = size
      }
    }
    var measured = Size.zero
    var cursor: Float = stack.reversed ? proposal[keyPath: main] : 0
    for index in range {
      let size = placements[index].size
      let extent = size[keyPath: main]
      if stack.reversed { cursor -= extent }
      placements[index].origin =
        stack.axis == .horizontal
        ? Point(x: cursor, y: stack.bottomAligned ? proposal.height - size.height : 0)
        : Point(x: 0, y: cursor)
      cursor += stack.reversed ? -stack.spacing : extent + stack.spacing
      measured[keyPath: main] += extent
      measured[keyPath: cross] = max(measured[keyPath: cross], size[keyPath: cross])
    }
    measured[keyPath: main] += stack.spacing * Float(max(0, range.count - 1))
    return (measured, range)
  }

  private mutating func stackPlacements(_ node: LayoutNode, proposal: Size) -> Range<Int> {
    _ = sizeThatFits(node, proposal)
    var index = nodes[node.index].measurements
    while index >= 0 {
      let entry = measurements[index]
      if entry.proposal == proposal { return entry.placements! }
      index = entry.next
    }
    preconditionFailure("Missing prepared stack layout")
  }

  private func placed(_ placement: Rect, in rect: Rect) -> Rect {
    Rect(
      x: rect.minX + placement.minX, y: rect.minY + placement.minY,
      width: placement.size.width, height: placement.size.height)
  }

}

/// Standalone operation ownership. Windows reuse a LayoutBuffer instead.
@MainActor
public struct PreparedLayout: ~Copyable {
  private var buffer: LayoutBuffer
  private let root: LayoutNode

  init(buffer: consuming LayoutBuffer, root: LayoutNode) {
    self.buffer = buffer
    self.root = root
  }

  public var nodeCount: Int { buffer.count }
  public var expandsHorizontally: Bool { mutating get { buffer.expandsHorizontally(root) } }
  public var expandsVertically: Bool { mutating get { buffer.expandsVertically(root) } }
  public mutating func sizeThatFits(_ proposal: Size) -> Size { buffer.sizeThatFits(root, proposal) }
  public mutating func register(in rect: Rect) { buffer.register(root, in: rect) }
  public mutating func paint(into list: inout DrawList, in rect: Rect) { buffer.paint(root, into: &list, in: rect) }
}
