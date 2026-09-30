struct CommandScope: PrimitiveBlock, CollectionDistributingBlock {
  enum Operation {
    case keyBindings(KeyBindings)
    case handler(Command, @MainActor () -> CommandResult)
  }

  var content: any Block
  var operation: Operation

  var preservesContentIdentity: Bool { true }

  var focusRule: FocusRule { .container }

  @MainActor var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    draw(into: &drawList, in: rect, context: context) { list, rect, context in
      BlockEngine.draw(content, into: &list, in: rect, context: context)
    }
  }

  @MainActor func draw(
    into drawList: inout DrawList, in rect: Rect, context: BlockContext,
    drawContent: (inout DrawList, Rect, BlockContext) -> Void
  ) {
    let interaction = context.interaction
    switch operation {
    case .keyBindings(let bindings):
      let bindingStart = interaction.building.keyBindingScopes.count
      interaction.beginGroup(rect: rect)
      interaction.building.keyBindingScopes.append(
        Interaction.ScopedKeyBindings(path: interaction.builderPath, bindings: bindings))
      drawContent(&drawList, rect, context)
      if !interaction.endGroup() {
        interaction.building.keyBindingScopes.removeSubrange(bindingStart...)
      }
    case .handler(let command, let action):
      let isRoot =
        interaction.builderPath.isEmpty
        && context.structuralPath.segments.allSatisfy {
          switch $0 {
          case .component, .key: true
          case .slot, .branch, .background: false
          }
        }
      if isRoot {
        drawContent(&drawList, rect, context)
        interaction.building.commandHandlers.append(
          Interaction.ScopedCommandHandler(path: [], command: command, action: action))
        return
      }
      let handlerStart = interaction.building.commandHandlers.count
      interaction.beginGroup(rect: rect)
      interaction.building.commandHandlers.append(
        Interaction.ScopedCommandHandler(
          path: interaction.builderPath, command: command, action: action))
      drawContent(&drawList, rect, context)
      if !interaction.endGroup() {
        interaction.building.commandHandlers.removeSubrange(handlerStart...)
      }
    }
  }
}
