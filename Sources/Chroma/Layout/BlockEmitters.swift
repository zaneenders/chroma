extension LayoutModifier {
  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let child = buffer.emit(content, context: context)
    return buffer.mapChildren(child, context: context) { buffer, child, context in
      buffer.node(.layout(child, operation), context: context)
    }
  }
}
extension PaintModifier {
  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let childContext: BlockContext
    if case .background = operation { childContext = context.backgroundContentContext } else { childContext = context }
    let child = buffer.emit(content, context: childContext)
    return buffer.mapChildren(child, context: context) { buffer, child, context in
      let decoration: LayoutBuffer.Decoration
      switch operation {
      case .background(let background):
        decoration = .background(buffer.emit(background, context: context.backgroundContext))
      case .roundedBackground(let color, let radii): decoration = .rounded(color, radii)
      case .border(let color, let radii, let width): decoration = .border(color, radii, width)
      case .clip: decoration = .clip
      }
      return buffer.node(.decoration(child, decoration), context: context)
    }
  }
}
extension ContextModifier {
  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    var context = context
    switch operation {
    case .hover(let style): context.hoverStyle = style
    case .navigationIgnored: context.navigationIgnored = true
    }
    return buffer.emit(content, context: context)
  }
}
extension CommandScope {
  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let child = buffer.emit(content, context: context)
    return buffer.mapChildren(child, context: context) { buffer, child, context in
      buffer.node(.command(child, operation), context: context)
    }
  }
}
extension Group {
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let context = context.component(Self.self)
    let child = buffer.emit(content, context: context)
    return buffer.node(.group(child, name), context: context)
  }
}
extension ThemeBlock {
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.emit(content, context: context.withTheme(theme))
  }
}
extension ThemeReader {
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.emit(content(context.theme), context: context)
  }
}
extension FocusTargetBlock {
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    var context = context
    context.focusTargets.append(target)
    let child = buffer.emit(content, context: context)
    return buffer.node(.focus(child, target), context: context)
  }
}
