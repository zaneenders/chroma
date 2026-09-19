import Testing

@testable import Chroma

struct KeyBindingsTests {
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
    #expect(KeyBindings.vimNavigation.command(for: KeyChord(.upArrow)) == .some(.some(.navigation(.up))))
    #expect(KeyBindings.vimNavigation.command(for: KeyChord(.rightArrow)) == .some(.some(.navigation(.right))))
  }

  @Test func overlayCanSpecializeBindingsForEditingWithoutReplacingNavigation() {
    let bindings = KeyBindings.vimNavigation.overlay {
      bind(.upArrow, to: .editing(.moveCaretUp))
      bind(.enter, to: .editing(.submit))
    }

    #expect(
      bindings.command(for: KeyChord(.upArrow), isTextEditing: false)
        == .some(.some(.navigation(.up))))
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
