extension Block {
  public func keyBindings(@KeyBindingsBuilder _ content: () -> [KeyBinding]) -> some Block {
    KeyBindingsBlock(content: self, bindings: KeyBindings(content))
  }

  public func keyBindings(_ bindings: KeyBindings) -> some Block {
    KeyBindingsBlock(content: self, bindings: bindings)
  }

  public func onCommand(
    _ command: Command,
    perform action: @escaping @MainActor () -> CommandResult
  ) -> some Block {
    CommandHandlerBlock(content: self, command: command, action: action)
  }
}
