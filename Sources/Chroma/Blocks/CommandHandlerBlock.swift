public struct CommandHandlerBlock: PrimitiveBlock, IdentityTransparentBlock {
  public var content: any Block
  public var command: Command
  public var action: @MainActor () -> CommandResult

  public init(content: any Block, command: Command, action: @escaping @MainActor () -> CommandResult) {
    self.content = content
    self.command = command
    self.action = action
  }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let interaction = context.interaction
    // Root handlers remain available even when the content has no focusable controls.
    let isRoot =
      interaction.builderPath.isEmpty
      && context.structuralPath.segments.allSatisfy {
        if case .component = $0 { return true }
        return false
      }
    if isRoot {
      BlockEngine.draw(content, into: &drawList, in: rect, context: context)
      interaction.buildingCommandHandlers.append(
        Interaction.ScopedCommandHandler(path: [], command: command, action: action))
      return
    }
    let handlerStart = interaction.buildingCommandHandlers.count
    interaction.beginGroup(rect: rect)
    interaction.buildingCommandHandlers.append(
      Interaction.ScopedCommandHandler(
        path: interaction.builderPath, command: command, action: action))
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
    if !interaction.endGroup() {
      interaction.buildingCommandHandlers.removeSubrange(handlerStart...)
    }
  }
}
