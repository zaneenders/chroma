/// A traversal owns its resolved children and measurements. Nothing is reused across input events or frames.
@MainActor
protocol LayoutPreparingBlock: PrimitiveBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved
}

extension LayoutModifier: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
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
      draw: { list, rect in
        draw(into: &list, in: rect, context: context) { list, rect, _ in
          child.draw(into: &list, in: rect)
        }
      })
  }
}

extension PaintModifier: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let childContext: BlockContext
    if case .background = operation { childContext = context.backgroundContentContext } else { childContext = context }
    let child = BlockEngine.resolve(content, context: childContext)
    return BlockEngine.Resolved(child: child) { list, rect in
      draw(into: &list, in: rect, context: context) { list, rect, _ in
        child.draw(into: &list, in: rect)
      }
    }
  }
}

extension ContextModifier: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    var context = context
    switch operation {
    case .hover(let style): context.hoverStyle = style
    case .navigationIgnored: context.navigationIgnored = true
    }
    return BlockEngine.resolve(content, context: context)
  }
}

extension CommandScope: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let child = BlockEngine.resolve(content, context: context)
    return BlockEngine.Resolved(child: child) { list, rect in
      draw(into: &list, in: rect, context: context) { list, rect, _ in
        child.draw(into: &list, in: rect)
      }
    }
  }
}

extension Group: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let child = BlockEngine.resolve(content, context: context)
    return BlockEngine.Resolved(child: child) { list, rect in
      context.interaction.beginGroup(rect: rect, navigationID: context.widgetID, navigationName: name)
      child.draw(into: &list, in: rect)
      context.interaction.endGroup()
    }
  }
}

extension ThemeBlock: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    BlockEngine.resolve(content, context: context.withTheme(theme))
  }
}

extension ThemeReader: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    let child = BlockEngine.resolve(content(context.theme), context: context)
    return BlockEngine.Resolved(
      expandsHorizontally: { false }, expandsVertically: { false },
      measure: child.sizeThatFits, draw: { list, rect in child.draw(into: &list, in: rect) })
  }
}

extension FocusTargetBlock: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    var context = context
    context.focusTargets.append(target)
    let child = BlockEngine.resolve(content, context: context)
    return BlockEngine.Resolved(child: child) { list, rect in
      _ = target.pendingEditing
      child.draw(into: &list, in: rect)
    }
  }
}

extension Interactive: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    // Expansion and every size proposal share the idle tree. Painting resolves the current phase
    // through the control's normal registration path, with its own focus-claimed child context.
    let idle = BlockEngine.resolve(content(.idle), context: context)
    return BlockEngine.Resolved(
      expandsHorizontally: { idle.expandsHorizontally },
      expandsVertically: { idle.expandsVertically },
      measure: idle.sizeThatFits,
      draw: { list, rect in BlockEngine.drawResolved(self, into: &list, in: rect, context: context) })
  }
}

extension HStack: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    StackLayout(axis: .horizontal, spacing: spacing, bottomAligned: alignment == .bottom)
      .prepare(scopedChildren, reversed: isLayoutReversed, context: context)
  }
}

extension VStack: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    StackLayout(axis: .vertical, spacing: spacing)
      .prepare(scopedChildren, reversed: isLayoutReversed, context: context)
  }
}

extension TupleBlock: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    BlockEngine.prepareOverlay(scopedChildren, group: false, context: context)
  }
}

extension ZStack: LayoutPreparingBlock {
  func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
    BlockEngine.prepareOverlay(scopedChildren, group: true, context: context)
  }
}

extension BlockEngine {
  static func prepareOverlay(_ originals: [any Block], group: Bool, context: BlockContext) -> Resolved {
    let children = originals.enumerated().map { index, child in
      resolve(child, context: context.childContext(for: child, at: index))
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
      draw: { list, rect in
        if group { context.interaction.beginGroup(rect: rect) }
        for child in children {
          let size = group ? child.sizeThatFits(rect.size) : rect.size
          child.draw(into: &list, in: Rect(origin: rect.origin, size: size))
        }
        if group { context.interaction.endGroup() }
      })
  }
}
