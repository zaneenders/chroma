@MainActor
extension Interaction {
  var activeCommandPath: [Int] {
    if let selection { return selection }
    if let selected = navigation?.node(at: navigationPath), selected.isGroup {
      if navigationPath.isEmpty, let first = selected.children.first {
        var common = first.renderPath
        for child in selected.children.dropFirst() {
          while !isPrefix(common, of: child.renderPath) { common.removeLast() }
        }
        return common
      }
      return selected.renderPath
    }
    return []
  }

  private func isPrefix(_ prefix: [Int], of path: [Int]) -> Bool {
    prefix.count <= path.count && Array(path.prefix(prefix.count)) == prefix
  }

  package func resolve(_ input: KeyboardInput, appBindings: KeyBindings) -> ResolvedKeyboardInput? {
    appBindings.resolve(input, isTextEditing: isTextEditing) { chord in
      keyBindingCommand(for: chord, isTextEditing: isTextEditing, appBindings: appBindings)
    }
  }

  private func keyBindingCommand(
    for chord: KeyChord, isTextEditing: Bool, appBindings: KeyBindings
  ) -> Command?? {
    for scope
      in registrations.keyBindingScopes
      .filter({ isPrefix($0.path, of: activeCommandPath) })
      .sorted(by: { $0.path.count > $1.path.count })
    {
      if let command = scope.bindings.command(for: chord, isTextEditing: isTextEditing) { return command }
    }
    return appBindings.command(for: chord, isTextEditing: isTextEditing)
  }

  func routePendingCommands() {
    for (index, command) in pendingCommands.enumerated() where !handledCommandIndices.contains(index) {
      if mode == .editing, command == .action(.cancel) || command == .action(.dismiss) {
        stopInput()
        handledCommandIndices.insert(index)
        continue
      }
      if editingLeaf != nil, command == .action(.cancel) || command == .action(.dismiss) {
        endEditing()
        handledCommandIndices.insert(index)
        continue
      }
      let handlers =
        registrations.commandHandlers
        .filter { $0.command == command && isPrefix($0.path, of: activeCommandPath) }
        .sorted { $0.path.count > $1.path.count }
      if handlers.contains(where: { $0.action() == .handled }) {
        handledCommandIndices.insert(index)
        continue
      }
      if case .navigation(let direction) = command,
        moveLogicalSelection(direction)
      {
        handledCommandIndices.insert(index)
        continue
      }
      switch command {
      case .action(.submit):
        actionRole(.defaultAction)?()
      case .action(.cancel), .action(.dismiss):
        if let action = actionRole(.cancel) {
          action()
        } else if mode == .editing {
          endEditing()
        }
      default:
        apply(command)
      }
    }
  }

  func actionRole(_ role: ActionRole) -> (@MainActor () -> Void)? {
    registrations.actionRoles
      .filter { $0.role == role && isPrefix($0.path, of: activeCommandPath) }
      .max { $0.path.count < $1.path.count }?
      .action
  }

  func apply(_ command: Command) {
    guard tree != nil else { return }
    switch command {
    case .application:
      return
    case .editing:
      return
    case .navigation(let command):
      if command == .nextFocus || command == .previousFocus {
        if isTextEditing { endEditing() }
        moveNavigation(command)
        return
      }
      guard mode == .movement else { return }
      if editingLeaf != nil {
        if [.sectionLeft, .sectionRight, .sectionUp, .sectionDown].contains(command) {
          endEditing()
          moveNavigation(command)
          return
        }
        switch command {
        case .left: movementTextEvents.append(.moveCaretLeft)
        case .right: movementTextEvents.append(.moveCaretRight)
        case .up: movementTextEvents.append(.moveCaretUp)
        case .down: movementTextEvents.append(.moveCaretDown)
        case .stepOut: endEditing()
        case .sectionLeft, .sectionRight, .sectionUp, .sectionDown: break
        case .stepIn, .nextFocus, .previousFocus: break
        }
        return
      }
      moveNavigation(command)
    case .action(.activate):
      guard let tree, let selection, tree.node(at: selection)?.isLeaf == true else { return }
      activatePending = true
    case .action(.submit), .action(.cancel), .action(.dismiss):
      return
    }
  }
}
