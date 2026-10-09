extension LayoutModifier {
  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let child = buffer.emit(content, context: context)
    switch operation {
    case .padding(let insets): return buffer.padding(child, insets, context: context)
    case .sizing(let x, let y): return buffer.sizing(child, x: x, y: y, context: context)
    }
  }
}
extension PaintModifier {
  @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    switch operation {
    case .background(let background):
      return buffer.background(
        context: context,
        content: { buffer, context in buffer.emit(content, context: context) },
        background: { buffer, context in buffer.emit(background, context: context) })
    case .roundedBackground(let color, let radii):
      let child = buffer.emit(content, context: context)
      return buffer.roundedBackground(child, color: color, radii: radii, context: context)
    case .border(let color, let radii, let width):
      let child = buffer.emit(content, context: context)
      return buffer.border(child, color: color, radii: radii, width: width, context: context)
    case .clip:
      let child = buffer.emit(content, context: context)
      return buffer.clip(child, context: context)
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
    switch operation {
    case .keyBindings(let bindings): return buffer.keyBindings(child, bindings, context: context)
    case .handler(let command, let action): return buffer.onCommand(child, command, context: context, action: action)
    }
  }
}
extension Group {
  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    buffer.group(name, context: context) { buffer, context in buffer.emit(content, context: context) }
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
    buffer.focus(target, context: context) { buffer, context in buffer.emit(content, context: context) }
  }
}
