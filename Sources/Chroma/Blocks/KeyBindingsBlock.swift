public struct KeyBindingsBlock: PrimitiveBlock, IdentityTransparentBlock {
  public var content: any Block
  public var bindings: KeyBindings

  public init(content: any Block, bindings: KeyBindings) {
    self.content = content
    self.bindings = bindings
  }

  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let interaction = context.interaction
    let bindingStart = interaction.buildingKeyBindingScopes.count
    interaction.beginGroup(rect: rect)
    interaction.buildingKeyBindingScopes.append(
      Interaction.ScopedKeyBindings(path: interaction.builderPath, bindings: bindings))
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
    if !interaction.endGroup() {
      interaction.buildingKeyBindingScopes.removeSubrange(bindingStart...)
    }
  }
}
