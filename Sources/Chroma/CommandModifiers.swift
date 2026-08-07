extension Block {
  public func onCommand(
    _ command: Command,
    perform action: @escaping @MainActor () -> CommandResult
  ) -> CommandHandlerBlock {
    CommandHandlerBlock(content: self, command: command, action: action)
  }

  public func keyBindings(@KeyBindingsBuilder _ bindings: () -> [KeyBinding]) -> KeyBindingBlock {
    KeyBindingBlock(content: self, bindings: KeyBindings(bindings))
  }
}

public struct CommandHandlerBlock: PrimitiveBlock {
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
    context.interaction.buildingCommandHandlers.append(
      Interaction.ScopedCommandHandler(
        path: context.interaction.builderPath, command: command, action: action))
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}

/// A focused keybinding scope. The current renderer resolves app bindings before drawing;
/// this wrapper records the intended local map API while scoped physical-key resolution is
/// completed by backends that can associate key events with the current focus path.
public struct KeyBindingBlock: PrimitiveBlock {
  public var content: any Block
  public var bindings: KeyBindings

  public init(content: any Block, bindings: KeyBindings) {
    self.content = content
    self.bindings = bindings
  }

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }
  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }
  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}
