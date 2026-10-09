import BasicContainers

/// A checked operation-local index. Persistent interaction state uses logical keys instead.
/// A node has one placement in a registered graph. Emit distinct nodes to repeat content;
/// sharing a handle between parents or sibling positions is unsupported.
public struct LayoutNode: Hashable, Sendable {
  fileprivate let owner: UInt64
  fileprivate let generation: UInt64
  fileprivate let index: Int
}

public enum FocusRule: Sendable { case standard, control, container, decorative }

/// One reusable owner for direct construction, layout, registration and ordered drawing.
@MainActor
public struct LayoutBuffer: ~Copyable {
  enum Content {
    case text(Text)
    case image(Image)
    case color(Color)
    case marquee(MarqueeText)
    case progress(ProgressIndicator)
    case button(Int)
    case editor(Int)
    case interactive(Int)
    case empty, spacer
    case stack(Stack)
    case overlay(Range<Int>, Bool)
    case layout(LayoutNode, LayoutOperation)
    case decoration(LayoutNode, Decoration)
    case group(LayoutNode, String?)
    case command(LayoutNode, CommandOperation)
    case animation(LayoutNode, ScalarAnimation)
    case trailing(LayoutNode, LayoutNode, Float)
    case scroll(Int)
    case custom(CustomLeaf)
  }
  enum Decoration {
    case background(LayoutNode)
    case rounded(Color, CornerRadii)
    case border(Color, CornerRadii, Float)
    case clip
  }
  struct ScrollNode {
    let scroll: ScrollView
    var prepared: ScrollView.PreparedScroll?
  }
  struct Record {
    var content: Content
    var horizontal: Bool?
    var vertical: Bool?
    var measurements = -1
    var registeredRect: Rect?
  }
  struct CustomLeaf {
    let focusRule: FocusRule
    let horizontal: Bool
    let vertical: Bool
    let measure: (Size) -> Size
    let register: (Rect) -> Void
    let paint: (inout DrawList, Rect) -> Void
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
  }
  struct Child {
    let node: LayoutNode
    let spacer: Bool
  }

  private static var nextOwner: UInt64 = 0
  private let owner: UInt64
  private var generation: UInt64 = 0
  private var nodes = BasicContainers.UniqueArray<Record>()
  private var contexts = BasicContainers.UniqueArray<LayoutContext>()
  private var buttons = BasicContainers.UniqueArray<Button>()
  private var editors = BasicContainers.UniqueArray<TextEditorNode>()
  private var interactives = BasicContainers.UniqueArray<InteractiveNode>()
  private var scrolls = BasicContainers.UniqueArray<ScrollNode>()
  private var measurements = BasicContainers.UniqueArray<Measurement>()
  private var children = BasicContainers.UniqueArray<Child>()
  private var placements = BasicContainers.UniqueArray<Rect>()
  private var paintingDepth = 0

  public init() {
    Self.nextOwner += 1
    owner = Self.nextOwner
  }
  public var count: Int { nodes.count }
  public var capacity: Int { nodes.capacity }

  public mutating func reset(releasingCapacity: Bool = false) {
    generation += 1
    contexts.removeAll()
    buttons.removeAll()
    editors.removeAll()
    interactives.removeAll()
    scrolls.removeAll()
    nodes.removeAll()
    measurements.removeAll()
    children.removeAll()
    placements.removeAll()
    if releasingCapacity {
      contexts = .init()
      buttons = .init()
      editors = .init()
      interactives = .init()
      scrolls = .init()
      nodes = .init()
      measurements = .init()
      children = .init()
      placements = .init()
    }
  }
  public func contains(_ node: LayoutNode) -> Bool {
    node.owner == owner && node.generation == generation && nodes.indices.contains(node.index)
  }
  mutating func node(_ content: Content, context: LayoutContext) -> LayoutNode {
    let node = LayoutNode(owner: owner, generation: generation, index: nodes.count)
    if nodes.count == nodes.capacity { PipelineMetrics.record(.bufferGrowth) }
    PipelineMetrics.record(.layoutNode)
    if contexts.count == contexts.capacity { PipelineMetrics.record(.bufferGrowth) }
    contexts.append(context)
    nodes.append(Record(content: content))
    return node
  }
  public mutating func text(_ text: Text, context: LayoutContext) -> LayoutNode {
    node(.text(text), context: context.component(Text.self))
  }
  public mutating func image(_ image: Image, context: LayoutContext) -> LayoutNode {
    node(.image(image), context: context.component(Image.self))
  }
  public mutating func color(_ color: Color, context: LayoutContext) -> LayoutNode {
    node(.color(color), context: context.component(Color.self))
  }
  public mutating func marqueeText(_ text: MarqueeText, context: LayoutContext) -> LayoutNode {
    node(.marquee(text), context: context.component(MarqueeText.self))
  }
  public mutating func progressIndicator(_ progress: ProgressIndicator, context: LayoutContext) -> LayoutNode {
    node(.progress(progress), context: context.component(ProgressIndicator.self))
  }
  public mutating func button(_ button: Button, context: LayoutContext) -> LayoutNode {
    let index = buttons.count
    if index == buttons.capacity { PipelineMetrics.record(.bufferGrowth) }
    buttons.append(button)
    return node(.button(index), context: context.component(Button.self))
  }
  public mutating func textEditor(_ editor: TextEditor, context: LayoutContext) -> LayoutNode {
    let context = context.component(TextEditor.self)
    let index = editors.count
    if index == editors.capacity { PipelineMetrics.record(.bufferGrowth) }
    editors.append(TextEditorNode(editor, context: context))
    return node(.editor(index), context: context)
  }
  public mutating func interactive(
    action: @escaping @MainActor () -> Void,
    content: @escaping @MainActor (inout LayoutBuffer, LayoutContext, InteractionPhase) -> LayoutNode,
    context: LayoutContext
  ) -> LayoutNode {
    interactive(id: nil, action: action, content: content, context: context)
  }
  mutating func interactive(
    id: WidgetID?, action: @escaping @MainActor () -> Void,
    content: @escaping @MainActor (inout LayoutBuffer, LayoutContext, InteractionPhase) -> LayoutNode,
    context: LayoutContext
  ) -> LayoutNode {
    let context = context.component(InteractiveNode.self)
    let index = interactives.count
    if index == interactives.capacity { PipelineMetrics.record(.bufferGrowth) }
    interactives.append(InteractiveNode(id: id, action: action, content: content, context: context))
    return node(.interactive(index), context: context)
  }
  public mutating func scrollView(_ scroll: ScrollView, context: LayoutContext) -> LayoutNode {
    let index = scrolls.count
    if index == scrolls.capacity { PipelineMetrics.record(.bufferGrowth) }
    scrolls.append(ScrollNode(scroll: scroll))
    return node(.scroll(index), context: context.component(ScrollView.self))
  }
  public mutating func spacer(context: LayoutContext) -> LayoutNode { node(.spacer, context: context) }
  public mutating func empty(context: LayoutContext) -> LayoutNode { node(.empty, context: context) }

  /// Narrow extension for an externally defined leaf. Built-in nodes use typed records.
  public mutating func customLeaf(
    context: LayoutContext, focusRule: FocusRule = .standard,
    expandsHorizontally: Bool = false, expandsVertically: Bool = false,
    measure: @escaping (Size) -> Size, register: @escaping (Rect) -> Void,
    paint: @escaping (inout DrawList, Rect) -> Void
  ) -> LayoutNode {
    node(
      .custom(
        CustomLeaf(
          focusRule: focusRule, horizontal: expandsHorizontally, vertical: expandsVertically,
          measure: measure, register: register, paint: paint)), context: context)
  }

  public mutating func expandsHorizontally(_ node: LayoutNode) -> Bool { expands(node, horizontally: true) }
  public mutating func expandsVertically(_ node: LayoutNode) -> Bool { expands(node, horizontally: false) }
  private mutating func expands(_ node: LayoutNode, horizontally: Bool) -> Bool {
    precondition(contains(node), "Stale layout handle")
    if let cached = horizontally ? nodes[node.index].horizontal : nodes[node.index].vertical { return cached }
    let value: Bool
    switch nodes[node.index].content {
    case .color, .spacer, .scroll: value = true
    case .editor, .trailing, .marquee: value = horizontally
    case .layout(_, .sizing(let x, let y)): value = (horizontally ? x : y) == .grow
    case .layout(let child, _), .decoration(let child, _), .group(let child, _), .command(let child, _),
      .animation(let child, _):
      value = expands(child, horizontally: horizontally)
    case .stack(let stack): value = stackExpands(stack, horizontally: horizontally)
    case .overlay(let range, _):
      value = range.contains { expands(children[$0].node, horizontally: horizontally) }
    case .interactive(let index):
      var state = interactives[index]
      value = horizontally ? state.expandsHorizontally(in: &self) : state.expandsVertically(in: &self)
      interactives[index] = state
    case .custom(let leaf): value = horizontally ? leaf.horizontal : leaf.vertical
    default: value = false
    }
    if horizontally { nodes[node.index].horizontal = value } else { nodes[node.index].vertical = value }
    return value
  }

  public mutating func sizeThatFits(_ node: LayoutNode, _ proposal: Size) -> Size {
    precondition(contains(node), "Stale layout handle")
    PipelineMetrics.record(.measurement)
    var cached = nodes[node.index].measurements
    while cached >= 0 {
      let entry = measurements[cached]
      if entry.proposal == proposal {
        PipelineMetrics.record(.measurementCacheHit)
        return entry.size
      }
      cached = entry.next
    }
    let context = contexts[node.index]
    let size: Size
    var layout: Range<Int>?
    switch nodes[node.index].content {
    case .text(let value): size = value.sizeThatFits(proposal, context: context)
    case .image(let value): size = value.sizeThatFits(proposal, context: context)
    case .marquee(let value): size = value.sizeThatFits(proposal, context: context)
    case .progress(let value): size = value.sizeThatFits(proposal, context: context)
    case .button(let index): size = buttons[index].sizeThatFits(proposal, context: context)
    case .editor(let index): size = editors[index].sizeThatFits(proposal)
    case .color, .spacer, .scroll: size = proposal
    case .empty: size = .zero
    case .custom(let leaf): size = leaf.measure(proposal)
    case .interactive(let index):
      var state = interactives[index]
      size = state.sizeThatFits(proposal, in: &self)
      interactives[index] = state
    case .layout(let child, let operation):
      size = LayoutOperation.sizeThatFits(operation, proposal: proposal) {
        sizeThatFits(child, $0)
      }
    case .decoration(let child, _), .group(let child, _), .command(let child, _),
      .animation(let child, _):
      size = sizeThatFits(child, proposal)
    case .stack(let stack): (size, layout) = placeStack(stack, proposal: proposal)
    case .overlay(let range, _):
      size = range.reduce(.zero) { result, index in
        let child = sizeThatFits(children[index].node, proposal)
        return Size(width: max(result.width, child.width), height: max(result.height, child.height))
      }
    case .trailing(let input, let controls, let spacing):
      let controlsSize = sizeThatFits(controls, proposal)
      let width = max(0, proposal.width - controlsSize.width - spacing)
      let inputSize = sizeThatFits(input, Size(width: width, height: proposal.height))
      size = Size(width: proposal.width, height: max(inputSize.height, controlsSize.height))
      layout = appendPlacements([
        Rect(x: 0, y: proposal.height - inputSize.height, width: width, height: inputSize.height),
        Rect(
          x: proposal.width - controlsSize.width, y: proposal.height - controlsSize.height,
          width: controlsSize.width, height: controlsSize.height),
      ])
    }
    let next = nodes[node.index].measurements
    nodes[node.index].measurements = measurements.count
    if measurements.count == measurements.capacity { PipelineMetrics.record(.bufferGrowth) }
    measurements.append(Measurement(proposal: proposal, size: size, next: next, placements: layout))
    return size
  }

  mutating func register(_ node: LayoutNode, in rect: Rect) {
    precondition(contains(node), "Stale layout handle")
    PipelineMetrics.record(.placement)
    PipelineMetrics.record(.registration)
    let context = contexts[node.index]
    let parent = context.interaction.builderStack.last
    let before = parent?.children.count
    var rule = FocusRule.container
    switch nodes[node.index].content {
    case .text(let value):
      value.register(in: rect, context: context)
      rule = .container
    case .image, .marquee: rule = .standard
    case .progress: rule = .decorative
    case .color: rule = .standard
    case .button(let index):
      buttons[index].register(in: rect, context: context)
      rule = .control
    case .editor(let index): editors[index].register(in: rect)
    case .interactive(let index):
      var state = interactives[index]
      state.register(in: rect, buffer: &self)
      interactives[index] = state
    case .custom(let leaf):
      leaf.register(rect)
      rule = leaf.focusRule
    case .layout(let child, let operation): register(child, in: LayoutOperation.placed(operation, in: rect))
    case .decoration(let child, let decoration):
      switch decoration {
      case .background(let background):
        register(background, in: rect)
        register(child, in: rect)
      case .clip: context.withInteractionClip(rect) { register(child, in: rect) }
      default: register(child, in: rect)
      }
    case .stack(let stack):
      let range = stackPlacements(node, proposal: rect.size)
      context.withFocusGroup(in: rect, axis: stack.axis) {
        for (childIndex, placementIndex) in zip(stack.children, range) {
          register(children[childIndex].node, in: placed(placements[placementIndex], in: rect))
        }
      }
    case .overlay(let range, let group):
      if group { context.interaction.beginGroup(rect: rect) }
      for index in range {
        let child = children[index].node
        register(child, in: Rect(origin: rect.origin, size: group ? sizeThatFits(child, rect.size) : rect.size))
      }
      if group { context.interaction.endGroup() }
    case .group(let child, let name):
      context.interaction.beginGroup(rect: rect, navigationID: context.widgetID, navigationName: name)
      register(child, in: rect)
      context.interaction.endGroup()
    case .command(let child, let operation):
      CommandOperation.withRegistration(operation, in: rect, context: context) { register(child, in: rect) }
    case .animation(let child, let state):
      context.interaction.animationKeys.insert(context.widgetID)
      context.interaction.animations[context.widgetID] = state
      register(child, in: rect)
    case .trailing(let input, let controls, _):
      let range = stackPlacements(node, proposal: rect.size)
      context.withFocusGroup(in: rect) {
        register(input, in: placed(placements[range.lowerBound], in: rect))
        register(controls, in: placed(placements[range.lowerBound + 1], in: rect))
      }
    case .scroll(let index):
      let scroll = scrolls[index].scroll
      let prepared = scroll.registerContent(in: rect, context: context, buffer: &self)
      scrolls[index].prepared = prepared
    case .empty, .spacer: break
    }
    if let parent, parent.children.count == before {
      if rule == .control { preconditionFailure("Control registered no focus leaf") }
      if rule == .standard, !context.focusLeafClaimed, !context.navigationIgnored {
        context.registerFocusable(in: rect)
      }
    }
    nodes[node.index].registeredRect = rect
  }

  mutating func paint(_ node: LayoutNode, into list: inout DrawList, in rect: Rect) {
    precondition(contains(node), "Stale layout handle")
    precondition(nodes[node.index].registeredRect == rect, "Drawing requires the committed layout rectangle")
    PipelineMetrics.record(.paint)
    let outermost = paintingDepth == 0
    let before = list.commands.count
    paintingDepth += 1
    defer {
      paintingDepth -= 1
      if outermost { PipelineMetrics.record(.drawingCommands, count: list.commands.count - before) }
    }
    let context = contexts[node.index]
    var highlight = false
    switch nodes[node.index].content {
    case .text(let value):
      value.paint(into: &list, in: rect, context: context)
      highlight = false
    case .image(let value):
      value.paint(into: &list, in: rect, context: context)
      highlight = true
    case .marquee(let value):
      value.paint(into: &list, in: rect, context: context)
      highlight = true
    case .progress(let value):
      value.paint(into: &list, in: rect, context: context)
      highlight = false
    case .color(let color):
      list.fillRect(rect, color: color)
      highlight = true
    case .button(let index): buttons[index].paint(into: &list, in: rect, context: context)
    case .editor(let index): editors[index].paint(into: &list, in: rect)
    case .interactive(let index):
      let state = interactives[index]
      state.paint(into: &list, in: rect, buffer: &self)
    case .custom(let leaf):
      leaf.paint(&list, rect)
      highlight = leaf.focusRule == .standard
    case .layout(let child, _): paint(child, into: &list, in: nodes[child.index].registeredRect!)
    case .decoration(let child, let decoration):
      switch decoration {
      case .background(let background):
        paint(background, into: &list, in: rect)
        paint(child, into: &list, in: rect)
      case .rounded(let color, let radii):
        list.fillRoundedRect(rect, radii: radii, color: color)
        paint(child, into: &list, in: rect)
      case .border(let color, let radii, let width):
        paint(child, into: &list, in: rect)
        if radii == .zero {
          list.strokeRect(rect, width: width, color: color)
        } else {
          list.strokeRoundedRect(rect, radii: radii, width: width, color: color)
        }
      case .clip:
        list.pushClip(rect)
        paint(child, into: &list, in: rect)
        list.popClip()
      }
    case .stack(let stack):
      for index in stack.children {
        let child = children[index].node
        paint(child, into: &list, in: nodes[child.index].registeredRect!)
      }
    case .overlay(let range, _):
      for index in range {
        let child = children[index].node
        paint(child, into: &list, in: nodes[child.index].registeredRect!)
      }
    case .group(let child, _), .command(let child, _), .animation(let child, _):
      paint(child, into: &list, in: rect)
    case .trailing(let input, let controls, _):
      paint(input, into: &list, in: nodes[input.index].registeredRect!)
      paint(controls, into: &list, in: nodes[controls.index].registeredRect!)
    case .scroll(let index):
      let state = scrolls[index]
      state.scroll.paint(state.prepared!, into: &list, context: context, buffer: &self)
    case .empty, .spacer: break
    }
    if highlight, !context.focusLeafClaimed, !context.navigationIgnored {
      context.paintFocusHighlight(in: rect, into: &list)
    }
  }

  private mutating func appendChildren(_ childNodes: [LayoutNode]) -> Range<Int> {
    let start = children.count
    for child in childNodes {
      precondition(contains(child), "Stale layout handle")
      if children.count == children.capacity { PipelineMetrics.record(.bufferGrowth) }
      let spacer: Bool
      if case .spacer = nodes[child.index].content { spacer = true } else { spacer = false }
      children.append(Child(node: child, spacer: spacer))
    }
    return start..<children.count
  }
  public mutating func overlay(_ childNodes: [LayoutNode], group: Bool = true, context: LayoutContext) -> LayoutNode {
    let range = appendChildren(childNodes)
    return node(.overlay(range, group), context: context)
  }
  public mutating func stack(
    _ childNodes: [LayoutNode], axis: FocusGroupAxis, spacing: Float = 0,
    reversed: Bool = false, bottomAligned: Bool = false, context: LayoutContext
  ) -> LayoutNode {
    let range = appendChildren(childNodes)
    return node(
      .stack(
        Stack(
          axis: axis, spacing: spacing, reversed: reversed,
          bottomAligned: bottomAligned, children: range)), context: context)
  }
  private mutating func appendPlacements(_ rects: [Rect]) -> Range<Int> {
    let start = placements.count
    for rect in rects {
      if placements.count == placements.capacity { PipelineMetrics.record(.bufferGrowth) }
      placements.append(rect)
    }
    return start..<placements.count
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
      if stack.axis == .horizontal ? expandsHorizontally(child.node) : expandsVertically(child.node) {
        expanders += 1
      } else {
        let size = sizeThatFits(child.node, proposal)
        placements[placement].size = size
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
