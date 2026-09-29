public struct CommandHandlerBlock: PrimitiveBlock, IdentityTransparentBlock {
  public var content: any Block
  public var command: Command
  public var action: @MainActor () -> CommandResult

  public init(content: any Block, command: Command, action: @escaping @MainActor () -> CommandResult) {
    self.content = content
    self.command = command
    self.action = action
  }

  public var focusRule: FocusRule { .container }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {
    let interaction = context.interaction
    let isRoot =
      interaction.builderPath.isEmpty
      && context.structuralPath.segments.allSatisfy {
        switch $0 {
        case .component, .key: true
        case .slot, .branch, .background: false
        }
      }
    if isRoot {
      BlockEngine.draw(content, into: &drawList, in: rect, context: context)
      interaction.building.commandHandlers.append(
        Interaction.ScopedCommandHandler(path: [], command: command, action: action))
      return
    }
    let handlerStart = interaction.building.commandHandlers.count
    interaction.beginGroup(rect: rect)
    interaction.building.commandHandlers.append(
      Interaction.ScopedCommandHandler(
        path: interaction.builderPath, command: command, action: action))
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
    if !interaction.endGroup() {
      interaction.building.commandHandlers.removeSubrange(handlerStart...)
    }
  }
}
