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
