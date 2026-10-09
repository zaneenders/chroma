/// Emit operation-local integer handles into the shared runtime buffer.
/// Callbacks and geometry are fresh for each update; allocated capacity can be reused.
///
/// This low-level extension point owns all registration and painting, including focus behavior:
/// the engine does not add automatic leaf focus to its prepared result.
/// Forward to prepared children, or explicitly register and paint any focus owned by this block.
/// Prefer `PaintableBlock` for ordinary leaves that need automatic primitive focus handling.
public protocol LayoutPreparingBlock: Block where Body == Never {
  var preservesContentIdentity: Bool { get }
  @MainActor func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode
}

/// Default entry points preserve direct primitive use; the engine prepares once and
/// owns its buffer through measurement, registration, and painting of one update.
extension LayoutPreparingBlock {
  public var preservesContentIdentity: Bool { false }
  public var body: Never { fatalError("\(Self.self) is a prepared block") }
  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    var prepared = BlockEngine.prepare(self, context: context)
    return prepared.sizeThatFits(proposal)
  }
  @MainActor public func register(in rect: Rect, context: BlockContext) {
    var prepared = BlockEngine.prepare(self, context: context)
    prepared.register(in: rect)
  }
}

extension LayoutModifier {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    let child = buffer.prepare(content, context: context)
    return buffer.append(
      expandsHorizontally: { buffer in
        if case .sizing(let x, _) = operation { return x == .grow }
        return buffer.expandsHorizontally(child)
      },
      expandsVertically: { buffer in
        if case .sizing(_, let y) = operation { return y == .grow }
        return buffer.expandsVertically(child)
      },
      measure: { buffer, proposal in
        sizeThatFits(proposal, context: context, measure: { buffer.sizeThatFits(child, $0) })
      },
      register: { buffer, rect in buffer.register(child, in: placedContent(in: rect)) },
      paint: { buffer, list, rect in buffer.paint(child, into: &list, in: placedContent(in: rect)) })
  }
}

extension PaintModifier {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    let childContext: BlockContext
    if case .background = operation { childContext = context.backgroundContentContext } else { childContext = context }
    let child = buffer.prepare(content, context: childContext)
    var preparedBackground: LayoutNode?
    return buffer.append(
      child: child,
      register: { buffer, rect in
        switch operation {
        case .background(let background):
          let background = buffer.prepare(background, context: context.backgroundContext)
          preparedBackground = background
          buffer.register(background, in: rect)
          buffer.register(child, in: rect)
        case .clip:
          context.withInteractionClip(rect) { buffer.register(child, in: rect) }
        case .roundedBackground, .border:
          buffer.register(child, in: rect)
        }
      },
      paint: { buffer, list, rect in
        switch operation {
        case .background:
          precondition(preparedBackground != nil, "Background painting requires a preceding update")
          if let preparedBackground { buffer.paint(preparedBackground, into: &list, in: rect) }
          buffer.paint(child, into: &list, in: rect)
        case .roundedBackground(let color, let radii):
          list.fillRoundedRect(rect, radii: radii, color: color)
          buffer.paint(child, into: &list, in: rect)
        case .border(let color, let radii, let width):
          buffer.paint(child, into: &list, in: rect)
          if radii == .zero {
            list.strokeRect(rect, width: width, color: color)
          } else {
            list.strokeRoundedRect(rect, radii: radii, width: width, color: color)
          }
        case .clip:
          list.pushClip(rect)
          buffer.paint(child, into: &list, in: rect)
          list.popClip()
        }
      })
  }
}

extension ContextModifier {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    var context = context
    switch operation {
    case .hover(let style): context.hoverStyle = style
    case .navigationIgnored: context.navigationIgnored = true
    }
    return buffer.prepare(content, context: context)
  }
}

extension CommandScope {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    let child = buffer.prepare(content, context: context)
    return buffer.append(
      child: child,
      register: { buffer, rect in
        withRegistration(in: rect, context: context) { buffer.register(child, in: rect) }
      },
      paint: { buffer, list, rect in buffer.paint(child, into: &list, in: rect) })
  }
}

extension Group {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    let child = buffer.prepare(content, context: context)
    return buffer.append(
      child: child,
      register: { buffer, rect in
        context.interaction.beginGroup(rect: rect, navigationID: context.widgetID, navigationName: name)
        buffer.register(child, in: rect)
        context.interaction.endGroup()
      },
      paint: { buffer, list, rect in buffer.paint(child, into: &list, in: rect) })
  }
}

extension ThemeBlock {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    buffer.prepare(content, context: context.withTheme(theme))
  }
}

extension ThemeReader {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    let child = buffer.prepare(content(context.theme), context: context)
    return buffer.append(
      measure: { $0.sizeThatFits(child, $1) }, register: { $0.register(child, in: $1) },
      paint: { buffer, list, rect in buffer.paint(child, into: &list, in: rect) })
  }
}

extension FocusTargetBlock {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    var context = context
    context.focusTargets.append(target)
    let child = buffer.prepare(content, context: context)
    return buffer.append(
      child: child,
      register: { buffer, rect in
        _ = target.pendingEditing
        buffer.register(child, in: rect)
      },
      paint: { buffer, list, rect in buffer.paint(child, into: &list, in: rect) })
  }
}

extension HStack {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    buffer.prepareStack(
      scopedChildren, axis: .horizontal, spacing: spacing, reversed: isLayoutReversed,
      bottomAligned: alignment == .bottom, context: context)
  }
}

extension VStack {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    buffer.prepareStack(scopedChildren, axis: .vertical, spacing: spacing, reversed: isLayoutReversed, context: context)
  }
}

extension TupleBlock {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    BlockEngine.prepareOverlay(scopedChildren, group: false, context: context, in: &buffer)
  }
}

extension ZStack {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    BlockEngine.prepareOverlay(scopedChildren, group: true, context: context, in: &buffer)
  }
}

extension BlockEngine {
  static func prepareOverlay(
    _ originals: [any Block], group: Bool, context: BlockContext, in buffer: inout LayoutBuffer
  ) -> LayoutNode {
    let children = originals.enumerated().map { index, child in
      buffer.prepare(child, context: context.childContext(for: child, at: index))
    }
    var placed: (Rect, [Rect])?
    func placements(in rect: Rect, buffer: inout LayoutBuffer) -> [Rect] {
      if let placed, placed.0 == rect { return placed.1 }
      let result = children.map { child in
        Rect(origin: rect.origin, size: group ? buffer.sizeThatFits(child, rect.size) : rect.size)
      }
      placed = (rect, result)
      return result
    }
    return buffer.append(
      expandsHorizontally: { buffer in children.contains { buffer.expandsHorizontally($0) } },
      expandsVertically: { buffer in children.contains { buffer.expandsVertically($0) } },
      measure: { buffer, proposal in
        children.reduce(.zero) { result, child in
          let size = buffer.sizeThatFits(child, proposal)
          return Size(width: max(result.width, size.width), height: max(result.height, size.height))
        }
      },
      register: { buffer, rect in
        if group { context.interaction.beginGroup(rect: rect) }
        for (child, rect) in zip(children, placements(in: rect, buffer: &buffer)) { buffer.register(child, in: rect) }
        if group { context.interaction.endGroup() }
      },
      paint: { buffer, list, rect in
        for (child, rect) in zip(children, placements(in: rect, buffer: &buffer)) {
          buffer.paint(child, into: &list, in: rect)
        }
      })
  }
}

extension TrailingControlsRow {
  @MainActor public func prepareLayout(context: BlockContext, in buffer: inout LayoutBuffer) -> LayoutNode {
    let input = buffer.prepare(input, context: context.childScope(0))
    let controls = buffer.prepare(controls, context: context.childScope(1))
    func sizes(_ proposal: Size, buffer: inout LayoutBuffer) -> (input: Size, controls: Size) {
      let controlsSize = buffer.sizeThatFits(controls, proposal)
      let inputWidth = max(0, proposal.width - controlsSize.width - spacing)
      let inputSize = buffer.sizeThatFits(input, Size(width: inputWidth, height: proposal.height))
      return (Size(width: inputWidth, height: inputSize.height), controlsSize)
    }
    var placed: (Rect, Rect, Rect)?
    func place(_ rect: Rect, buffer: inout LayoutBuffer, visit: (inout LayoutBuffer, LayoutNode, Rect) -> Void) {
      if placed?.0 != rect {
        let sizes = sizes(rect.size, buffer: &buffer)
        placed = (
          rect,
          Rect(
            x: rect.minX, y: rect.maxY - sizes.input.height,
            width: sizes.input.width, height: sizes.input.height),
          Rect(
            x: rect.maxX - sizes.controls.width, y: rect.maxY - sizes.controls.height,
            width: sizes.controls.width, height: sizes.controls.height)
        )
      }
      visit(&buffer, input, placed!.1)
      visit(&buffer, controls, placed!.2)
    }
    return buffer.append(
      expandsHorizontally: { _ in true },
      measure: { buffer, proposal in
        let sizes = sizes(proposal, buffer: &buffer)
        return Size(width: proposal.width, height: max(sizes.input.height, sizes.controls.height))
      },
      register: { buffer, rect in
        context.withFocusGroup(in: rect) {
          place(rect, buffer: &buffer) { buffer, child, rect in buffer.register(child, in: rect) }
        }
      },
      paint: { buffer, list, rect in
        place(rect, buffer: &buffer) { buffer, child, rect in buffer.paint(child, into: &list, in: rect) }
      })
  }
}
