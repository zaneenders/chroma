enum CommandOperation {
  case keyBindings(KeyBindings)
  case handler(Command, @MainActor () -> CommandResult)

  @MainActor static func withRegistration(
    _ operation: CommandOperation, in rect: Rect, context: LayoutContext, content: () -> Void
  ) {
    let interaction = context.interaction
    switch operation {
    case .keyBindings(let bindings):
      let bindingStart = interaction.building.keyBindingScopes.count
      interaction.beginGroup(rect: rect)
      interaction.building.keyBindingScopes.append(
        Interaction.ScopedKeyBindings(path: interaction.builderPath, bindings: bindings))
      content()
      if !interaction.endGroup() {
        interaction.building.keyBindingScopes.removeSubrange(bindingStart...)
      }
    case .handler(let command, let action):
      let isRoot =
        interaction.builderPath.isEmpty
        && context.structuralPath.segments.allSatisfy {
          switch $0 {
          case .component, .key: true
          case .slot, .background: false
          }
        }
      if isRoot {
        content()
        interaction.building.commandHandlers.append(
          Interaction.ScopedCommandHandler(path: [], command: command, action: action))
        return
      }
      let handlerStart = interaction.building.commandHandlers.count
      interaction.beginGroup(rect: rect)
      interaction.building.commandHandlers.append(
        Interaction.ScopedCommandHandler(
          path: interaction.builderPath, command: command, action: action))
      content()
      if !interaction.endGroup() {
        interaction.building.commandHandlers.removeSubrange(handlerStart...)
      }
    }
  }
}
