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
