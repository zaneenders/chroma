import Testing

@testable import Chroma

struct KeyBindingsTests {
  @Test func physicalCommandAndSuperAreDistinct() {
    #expect(KeyModifiers.command != KeyModifiers.superKey)
    #expect(!KeyModifiers.command.contains(.superKey))
    #expect(!KeyModifiers.superKey.contains(.command))
  }

  @Test func primaryUsesThePlatformApplicationModifier() {
    #if os(macOS)
    #expect(KeyModifiers.primary == .command)
    #elseif os(Linux)
    #expect(KeyModifiers.primary == .superKey)
    #else
    #expect(KeyModifiers.primary == .control)
    #endif
  }

  @Test func primaryCombinesWithOtherModifiers() {
    let bindings = KeyBindings {
      bind("l", modifiers: [.primary, .shift], to: .editing(.selectAll))
    }

    #expect(
      bindings.command(for: KeyChord("l", modifiers: [.primary, .shift]))
        == .some(.some(.editing(.selectAll))))
    #expect(bindings.command(for: KeyChord("l", modifiers: .primary)) == nil)
  }
}
