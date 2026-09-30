extension Block {
  public func keyBindings(@KeyBindingsBuilder _ content: () -> [KeyBinding]) -> some Block {
    CommandScope(content: self, operation: .keyBindings(KeyBindings(content)))
  }

  public func keyBindings(_ bindings: KeyBindings) -> some Block {
    CommandScope(content: self, operation: .keyBindings(bindings))
  }

  public func onCommand(
    _ command: Command,
    perform action: @escaping @MainActor () -> CommandResult
  ) -> some Block {
    CommandScope(content: self, operation: .handler(command, action))
  }
}
