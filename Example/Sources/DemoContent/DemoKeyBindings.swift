import Chroma

@MainActor
func demoKeyBindings(shortcutModifier: KeyModifiers) -> KeyBindings {
  var bindings = KeyBindings.modalNavigation.overlay {
    bind("c", modifiers: shortcutModifier, to: .editing(.copy))
    bind("x", modifiers: shortcutModifier, to: .editing(.cut))
    bind("v", modifiers: shortcutModifier, to: .editing(.paste))
    bind("a", modifiers: shortcutModifier, to: .editing(.selectAll))
    bind(.backspace, to: .editing(.backspace))
    bind(.delete, to: .editing(.deleteForward))
    bind(.enter, to: .editing(.submit))
  }
  for key: Key in [.tab, .leftArrow, .rightArrow, .upArrow, .downArrow] {
    bindings = bindings.overlay {
      disable(key)
      disable(key, modifiers: .shift)
      disable(key, modifiers: .option)
      disable(key, modifiers: [.option, .shift])
    }
  }
  #if os(Linux)
  if shortcutModifier == .control || shortcutModifier == .superKey {
    let alternate: KeyModifiers = shortcutModifier == .control ? .superKey : .control
    bindings = bindings.overlay {
      bind("c", modifiers: alternate, to: .editing(.copy))
      bind("x", modifiers: alternate, to: .editing(.cut))
      bind("v", modifiers: alternate, to: .editing(.paste))
      bind("a", modifiers: alternate, to: .editing(.selectAll))
    }
  }
  #endif
  return bindings
}

var demoShortcutModifier: KeyModifiers {
  #if os(macOS)
  .command
  #else
  .control
  #endif
}
