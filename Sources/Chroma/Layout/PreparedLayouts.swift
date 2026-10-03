/// A traversal owns its resolved children and measurements. Nothing is reused across input events or frames.
///
/// This low-level extension point owns all registration and painting, including focus behavior:
/// the engine does not add automatic leaf focus to its prepared result.
/// Forward to prepared children, or explicitly register and paint any focus owned by this block.
/// Prefer `PaintableBlock` for ordinary leaves that need automatic primitive focus handling.
public protocol LayoutPreparingBlock: Block where Body == Never {
  var preservesContentIdentity: Bool { get }
  @MainActor func prepareLayout(context: BlockContext) -> BlockEngine.Resolved
}

/// Default entry points preserve direct primitive use; the engine prepares once and
/// owns this object through measurement, registration, and painting of one update.
extension LayoutPreparingBlock {
  public var preservesContentIdentity: Bool { false }
  public var body: Never { fatalError("\(Self.self) is a prepared block") }
  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    prepareLayout(context: context).sizeThatFits(proposal)
  }
  @MainActor public func register(in rect: Rect, context: BlockContext) {
    prepareLayout(context: context).register(in: rect)
  }
  @MainActor public func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {

    prepareLayout(context: context).draw(into: &list, in: rect)
  }
}

extension LayoutModifier {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let child = BlockEngine.resolve(content, context: context)
    return BlockEngine.Resolved(
      expandsHorizontally: {
        if case .sizing(let x, _) = operation { return x == .grow }
        return child.expandsHorizontally
      },
      expandsVertically: {
        if case .sizing(_, let y) = operation { return y == .grow }
        return child.expandsVertically
      },
      measure: { proposal in sizeThatFits(proposal, context: context, measure: child.sizeThatFits) },
      register: { rect in child.register(in: placedContent(in: rect)) },
      paint: { list, rect in child.paint(into: &list, in: placedContent(in: rect)) })
  }
}

extension PaintModifier {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let childContext: BlockContext
    if case .background = operation { childContext = context.backgroundContentContext } else { childContext = context }
    let child = BlockEngine.resolve(content, context: childContext)
    var preparedBackground: BlockEngine.Resolved?
    return BlockEngine.Resolved(
      child: child,
      register: { rect in
        switch operation {
        case .background(let background):
          let background = BlockEngine.resolve(background, context: context.backgroundContext)
          preparedBackground = background
          background.register(in: rect)
          child.register(in: rect)
        case .clip:
          context.withInteractionClip(rect) { child.register(in: rect) }
        case .roundedBackground, .border:
          child.register(in: rect)
        }
      },
      paint: { list, rect in
        switch operation {
        case .background:
          precondition(preparedBackground != nil, "Background painting requires a preceding update")
          preparedBackground?.paint(into: &list, in: rect)
          child.paint(into: &list, in: rect)
        case .roundedBackground(let color, let radii):
          list.fillRoundedRect(rect, radii: radii, color: color)
          child.paint(into: &list, in: rect)
        case .border(let color, let radii, let width):
          child.paint(into: &list, in: rect)
          if radii == .zero {
            list.strokeRect(rect, width: width, color: color)
          } else {
            list.strokeRoundedRect(rect, radii: radii, width: width, color: color)
          }
        case .clip:
          list.pushClip(rect)
          child.paint(into: &list, in: rect)
          list.popClip()
        }
      })
  }
}

extension ContextModifier {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    var context = context
    switch operation {
    case .hover(let style): context.hoverStyle = style
    case .navigationIgnored: context.navigationIgnored = true
    }
    return BlockEngine.resolve(content, context: context)
  }
}

extension CommandScope {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let child = BlockEngine.resolve(content, context: context)
    return BlockEngine.Resolved(
      child: child,
      register: { rect in
        withRegistration(in: rect, context: context) { child.register(in: rect) }
      },
      paint: { list, rect in child.paint(into: &list, in: rect) })
  }
}

extension Group {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let child = BlockEngine.resolve(content, context: context)
    return BlockEngine.Resolved(
      child: child,
      register: { rect in
        context.interaction.beginGroup(rect: rect, navigationID: context.widgetID, navigationName: name)
        child.register(in: rect)
        context.interaction.endGroup()
      },
      paint: { list, rect in child.paint(into: &list, in: rect) })
  }
}

extension ThemeBlock {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    BlockEngine.resolve(content, context: context.withTheme(theme))
  }
}

extension ThemeReader {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let child = BlockEngine.resolve(content(context.theme), context: context)
    return BlockEngine.Resolved(
      expandsHorizontally: { false }, expandsVertically: { false },
      measure: child.sizeThatFits, register: child.register,
      paint: { list, rect in child.paint(into: &list, in: rect) })
  }
}

extension FocusTargetBlock {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    var context = context
    context.focusTargets.append(target)
    let child = BlockEngine.resolve(content, context: context)
    return BlockEngine.Resolved(
      child: child,
      register: { rect in
        _ = target.pendingEditing
        child.register(in: rect)
      },
      paint: { list, rect in child.paint(into: &list, in: rect) })
  }
}

extension HStack {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    StackLayout(axis: .horizontal, spacing: spacing, bottomAligned: alignment == .bottom)
      .prepare(scopedChildren, reversed: isLayoutReversed, context: context)
  }
}

extension VStack {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    StackLayout(axis: .vertical, spacing: spacing)
      .prepare(scopedChildren, reversed: isLayoutReversed, context: context)
  }
}

extension TupleBlock {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    BlockEngine.prepareOverlay(scopedChildren, group: false, context: context)
  }
}

extension ZStack {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    BlockEngine.prepareOverlay(scopedChildren, group: true, context: context)
  }
}

extension BlockEngine {
  static func prepareOverlay(_ originals: [any Block], group: Bool, context: BlockContext) -> Resolved {
    let children = originals.enumerated().map { index, child in
      resolve(child, context: context.childContext(for: child, at: index))
    }
    var placed: (Rect, [Rect])?
    func placements(in rect: Rect) -> [Rect] {
      if let placed, placed.0 == rect { return placed.1 }
      let result = children.map { child in
        Rect(origin: rect.origin, size: group ? child.sizeThatFits(rect.size) : rect.size)
      }
      placed = (rect, result)
      return result
    }
    return Resolved(
      expandsHorizontally: { children.contains { $0.expandsHorizontally } },
      expandsVertically: { children.contains { $0.expandsVertically } },
      measure: { proposal in
        children.reduce(.zero) { result, child in
          let size = child.sizeThatFits(proposal)
          return Size(width: max(result.width, size.width), height: max(result.height, size.height))
        }
      },
      register: { rect in
        if group { context.interaction.beginGroup(rect: rect) }
        for (child, rect) in zip(children, placements(in: rect)) { child.register(in: rect) }
        if group { context.interaction.endGroup() }
      },
      paint: { list, rect in
        for (child, rect) in zip(children, placements(in: rect)) { child.paint(into: &list, in: rect) }
      })
  }
}

extension TrailingControlsRow {
  @MainActor public func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let input = BlockEngine.resolve(input, context: context.childScope(0))
    let controls = BlockEngine.resolve(controls, context: context.childScope(1))
    func sizes(_ proposal: Size) -> (input: Size, controls: Size) {
      let controlsSize = controls.sizeThatFits(proposal)
      let inputWidth = max(0, proposal.width - controlsSize.width - spacing)
      let inputSize = input.sizeThatFits(Size(width: inputWidth, height: proposal.height))
      return (Size(width: inputWidth, height: inputSize.height), controlsSize)
    }
    var placed: (Rect, Rect, Rect)?
    func place(_ rect: Rect, visit: (BlockEngine.Resolved, Rect) -> Void) {
      if placed?.0 != rect {
        let sizes = sizes(rect.size)
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
      visit(input, placed!.1)
      visit(controls, placed!.2)
    }
    return BlockEngine.Resolved(
      expandsHorizontally: { true }, expandsVertically: { false },
      measure: { proposal in
        let sizes = sizes(proposal)
        return Size(width: proposal.width, height: max(sizes.input.height, sizes.controls.height))
      },
      register: { rect in
        context.withFocusGroup(in: rect) { place(rect) { child, rect in child.register(in: rect) } }
      },
      paint: { list, rect in place(rect) { child, rect in child.paint(into: &list, in: rect) } })
  }
}
