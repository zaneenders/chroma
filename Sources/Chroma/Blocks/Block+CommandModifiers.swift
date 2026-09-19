extension Block {
  public func onCommand(
    _ command: Command,
    perform action: @escaping @MainActor () -> CommandResult
  ) -> CommandHandlerBlock {
    CommandHandlerBlock(content: self, command: command, action: action)
  }
}
