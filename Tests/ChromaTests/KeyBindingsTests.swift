import Testing

@testable import Chroma

struct KeyBindingsTests {
  @Test func desktopBindingsKeepNavigationAndEditingSeparate() {
    let bindings = KeyBindings.desktopNavigation
    #expect(bindings.command(for: KeyChord(.downArrow), isTextEditing: false) == .some(.some(.navigation(.down))))
    #expect(bindings.command(for: KeyChord(.downArrow), isTextEditing: true) == .some(.some(.editing(.moveCaretDown))))
    #expect(
      bindings.command(for: KeyChord(.leftArrow, modifiers: .shift), isTextEditing: true)
        == .some(.some(.editing(.selectCaretLeft))))
    #expect(bindings.command(for: KeyChord(.tab), isTextEditing: true) == .some(.some(.navigation(.nextFocus))))
    #expect(
      bindings.command(for: KeyChord(.tab, modifiers: .shift), isTextEditing: false)
        == .some(.some(.navigation(.previousFocus))))
    #expect(bindings.resolve(KeyboardInput(chord: KeyChord("j"), text: "j"), isTextEditing: false) == nil)
    #expect(
      KeyBindings.vimNavigation.command(for: KeyChord("j"), isTextEditing: false)
        == .some(.some(.navigation(.down))))
  }

  @Test func physicalCommandAndSuperAreDistinct() {
    #expect(KeyModifiers.command != KeyModifiers.superKey)
    #expect(!KeyModifiers.command.contains(.superKey))
    #expect(!KeyModifiers.superKey.contains(.command))
  }

  @Test func physicalModifiersCombineWithOtherModifiers() {
    for systemModifier in [KeyModifiers.command, .superKey] {
      let bindings = KeyBindings {
        bind("l", modifiers: [systemModifier, .shift], to: .editing(.selectAll))
      }

      #expect(
        bindings.command(for: KeyChord("l", modifiers: [systemModifier, .shift]))
          == .some(.some(.editing(.selectAll))))
      #expect(bindings.command(for: KeyChord("l", modifiers: systemModifier)) == nil)
    }
  }

  @Test func clipboardBindingsApplyOutsideTextEditing() {
    let bindings = KeyBindings {
      bind("a", modifiers: .command, to: .editing(.selectAll))
      bind("c", modifiers: .command, to: .editing(.copy))
    }

    #expect(
      bindings.resolve(
        KeyboardInput(chord: KeyChord("a", modifiers: .command)), isTextEditing: false)
        == .text(.selectAll))
    #expect(
      bindings.resolve(
        KeyboardInput(chord: KeyChord("c", modifiers: .command)), isTextEditing: false)
        == .text(.copy))
  }
}

struct KeyboardInputResolutionTests {
  @Test func resolvesTextAndCommandsIndependentlyOfTheBackend() {
    let bindings = KeyBindings.vimNavigation.overlay {
      bind(.upArrow, to: .editing(.moveCaretUp))
      bind("x", modifiers: .control, to: .application("close"))
    }

    #expect(
      bindings.resolve(KeyboardInput(chord: KeyChord("j"), text: "j"), isTextEditing: false)
        == .command(.navigation(.down)))
    #expect(
      bindings.resolve(KeyboardInput(chord: KeyChord("j"), text: "j"), isTextEditing: true)
        == .text(.insert("j")))
    #expect(
      bindings.resolve(KeyboardInput(chord: KeyChord(.upArrow)), isTextEditing: true)
        == .text(.moveCaretUp))
    #expect(
      bindings.resolve(
        KeyboardInput(chord: KeyChord("x", modifiers: .control), text: "x"), isTextEditing: true)
        == .command(.application("close")))
  }

  @Test func disabledBindingsSuppressTextInsertion() {
    let bindings = KeyBindings { disable("x", in: .editing) }

    #expect(bindings.resolve(KeyboardInput(chord: KeyChord("x"), text: "x"), isTextEditing: true) == nil)
  }
}

struct TextInsertionRoutingTests {
  @Test func printableShortcutsRemainTextWhileEditing() {
    for (chord, text) in [
      (KeyChord(.space), " "), (KeyChord("f"), "f"), (KeyChord("j"), "j"), (KeyChord("f", modifiers: .shift), "F"),
    ] {
      #expect(KeyBindings().prefersTextInsertion(chord: chord, text: text, isTextEditing: true))
      #expect(!KeyBindings().prefersTextInsertion(chord: chord, text: text, isTextEditing: false))
    }
  }

  @Test func defaultActivationIsMovementOnly() {
    for key: Key in [.enter, .space] {
      #expect(
        KeyBindings.vimNavigation.command(for: KeyChord(key), isTextEditing: false)
          == .some(.some(.action(.activate))))
      #expect(KeyBindings.vimNavigation.command(for: KeyChord(key), isTextEditing: true) == nil)
    }
  }

  @Test func editingBindingsPreserveSpaceInsertionWithNavigationPreset() {
    let bindings = KeyBindings.vimNavigation.overlay {
      bind(.backspace, to: .editing(.backspace))
      bind(.leftArrow, to: .editing(.moveCaretLeft))
      bind(.enter, to: .editing(.submit))
    }

    #expect(
      bindings.resolve(KeyboardInput(chord: KeyChord(.space), text: " "), isTextEditing: true)
        == .text(.insert(" ")))
    #expect(
      bindings.resolve(KeyboardInput(chord: KeyChord(.enter)), isTextEditing: true)
        == .text(.submit))
  }

  @Test func modifiedShortcutsAndNonTextKeysKeepTheirBindings() {
    for modifier: KeyModifiers in [.command, .control, .superKey] {
      #expect(
        !KeyBindings().prefersTextInsertion(
          chord: KeyChord("v", modifiers: modifier), text: "v", isTextEditing: true))
    }
    #expect(!KeyBindings().prefersTextInsertion(chord: KeyChord(.enter), text: nil, isTextEditing: true))
    #expect(!KeyBindings().prefersTextInsertion(chord: KeyChord(.space), text: "", isTextEditing: true))
  }
}

extension KeyBindingsTests {
  @Test func vimNavigationBindingsResolveAndPreserveTextInsertion() {
    for (character, command) in [
      ("f", NavigationCommand.up),
      ("j", .down),
      ("d", .left),
      ("k", .right),
    ] {
      #expect(
        KeyBindings.vimNavigation.command(for: KeyChord(Character(character)))
          == .some(.some(.navigation(command))))
      #expect(
        KeyBindings.vimNavigation.prefersTextInsertion(
          chord: KeyChord(Character(character)), text: character, isTextEditing: true))
    }
    for (key, direction, selection) in [
      ("d", NavigationCommand.sectionLeft, TextEditEvent.selectCaretLeft),
      ("f", .sectionUp, .selectCaretUp),
      ("j", .sectionDown, .selectCaretDown),
      ("k", .sectionRight, .selectCaretRight),
    ] {
      #expect(
        KeyBindings.vimNavigation.command(for: KeyChord(Character(key), modifiers: .control), isTextEditing: false)
          == .some(.some(.navigation(direction))))
      #expect(
        KeyBindings.vimNavigation.command(for: KeyChord(Character(key), modifiers: .shift), isTextEditing: false)
          == .some(.some(.editing(selection))))
      #expect(
        KeyBindings.vimNavigation.prefersTextInsertion(
          chord: KeyChord(Character(key), modifiers: .shift), text: key.uppercased(), isTextEditing: true))
    }
    #expect(
      KeyBindings.vimNavigation.command(for: KeyChord(.upArrow), isTextEditing: false) == nil
    )
    #expect(
      KeyBindings.vimNavigation.command(for: KeyChord(.rightArrow), isTextEditing: false) == nil)
  }

  @Test func overlayCanSpecializeBindingsForEditingWithoutReplacingNavigation() {
    let bindings = KeyBindings.vimNavigation.overlay {
      bind(.upArrow, to: .editing(.moveCaretUp))
      bind(.enter, to: .editing(.submit))
    }

    #expect(
      bindings.command(for: KeyChord(.upArrow), isTextEditing: false) == nil)
    #expect(
      bindings.command(for: KeyChord(.upArrow), isTextEditing: true)
        == .some(.some(.editing(.moveCaretUp))))
    #expect(
      bindings.command(for: KeyChord(.enter), isTextEditing: false)
        == .some(.some(.action(.activate))))
    #expect(
      bindings.command(for: KeyChord(.enter), isTextEditing: true)
        == .some(.some(.editing(.submit))))
  }

  @Test func activeContextTakesPrecedenceOverSharedBindings() {
    let bindings = KeyBindings {
      bind("x", in: .shared, to: .application("shared"))
      bind("x", in: .movement, to: .application("movement"))
      bind("x", in: .editing, to: .application("editing"))
    }

    #expect(
      bindings.command(for: KeyChord("x"), isTextEditing: false)
        == .some(.some(.application("movement"))))
    #expect(
      bindings.command(for: KeyChord("x"), isTextEditing: true)
        == .some(.some(.application("editing"))))
  }

  @Test func laterBindingsReplaceTheirContextOnly() {
    let bindings = KeyBindings {
      bind("x", in: .shared, to: .application("first"))
      bind("x", in: .movement, to: .application("movement"))
      bind("x", in: .shared, to: .application("last"))
    }

    #expect(
      bindings.command(for: KeyChord("x"), isTextEditing: false)
        == .some(.some(.application("movement"))))
    #expect(
      bindings.command(for: KeyChord("x"), isTextEditing: true)
        == .some(.some(.application("last"))))
  }
}

extension KeyBindingsTests {
  @Test func changingContextUpdatesRegistrationAndOverlays() {
    var binding = bind("x", to: .application("action"))
    binding.context = .editing
    let bindings = KeyBindings { binding }
    for candidate in [bindings, KeyBindings().overlay { binding }, KeyBindings().overlay(bindings)] {
      #expect(candidate.command(for: KeyChord("x"), isTextEditing: false) == nil)
      #expect(
        candidate.command(for: KeyChord("x"), isTextEditing: true)
          == .some(.some(.application("action"))))
    }
  }

  @Test func changingDisableContextNarrowsItsScope() {
    var binding = disable("x")
    binding.context = .editing
    let bindings = KeyBindings { binding }
    #expect(bindings.command(for: KeyChord("x"), isTextEditing: false) == nil)
    #expect(bindings.command(for: KeyChord("x"), isTextEditing: true) == .some(nil))
  }

  @Test func disableWithoutContextSuppressesAllContexts() {
    let bindings = KeyBindings.vimNavigation.overlay {
      disable(.upArrow)
    }

    #expect(bindings.command(for: KeyChord(.upArrow), isTextEditing: false) == .some(nil))
    #expect(bindings.command(for: KeyChord(.upArrow), isTextEditing: true) == .some(nil))
  }

  @Test func disableCanTargetOneContext() {
    let bindings = KeyBindings.vimNavigation.overlay {
      disable(.upArrow, in: .movement)
    }

    #expect(bindings.command(for: KeyChord(.upArrow), isTextEditing: false) == .some(nil))
    #expect(bindings.command(for: KeyChord(.upArrow), isTextEditing: true) == nil)
  }
}
