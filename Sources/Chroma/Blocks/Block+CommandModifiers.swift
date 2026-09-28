extension Block {
  public func keyBindings(@KeyBindingsBuilder _ content: () -> [KeyBinding]) -> KeyBindingsBlock {
    KeyBindingsBlock(content: self, bindings: KeyBindings(content))
  }

  public func keyBindings(_ bindings: KeyBindings) -> KeyBindingsBlock {
    KeyBindingsBlock(content: self, bindings: bindings)
  }

  public func onCommand(
    _ command: Command,
    perform action: @escaping @MainActor () -> CommandResult
  ) -> CommandHandlerBlock {
    CommandHandlerBlock(content: self, command: command, action: action)
  }
}
