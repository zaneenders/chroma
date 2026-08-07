public enum Key: Hashable, Sendable {
  case character(Character)
  case upArrow, downArrow, leftArrow, rightArrow
  case tab, enter, escape, space
  case home, end, pageUp, pageDown
  case delete, backspace
}

public struct KeyModifiers: OptionSet, Hashable, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let shift = Self(rawValue: 1 << 0)
  public static let control = Self(rawValue: 1 << 1)
  public static let option = Self(rawValue: 1 << 2)
  public static let command = Self(rawValue: 1 << 3)
}

public struct KeyChord: Hashable, Sendable {
  public var key: Key
  public var modifiers: KeyModifiers

  public init(_ key: Key, modifiers: KeyModifiers = []) {
    self.key = key
    self.modifiers = modifiers
  }

  public init(_ character: Character, modifiers: KeyModifiers = []) {
    self.init(.character(character), modifiers: modifiers)
  }
}

@resultBuilder
public enum KeyBindingsBuilder {
  public static func buildBlock(_ components: KeyBinding...) -> [KeyBinding] { components }
  public static func buildArray(_ components: [[KeyBinding]]) -> [KeyBinding] { components.flatMap { $0 } }
  public static func buildOptional(_ component: [KeyBinding]?) -> [KeyBinding] { component ?? [] }
  public static func buildEither(first component: [KeyBinding]) -> [KeyBinding] { component }
  public static func buildEither(second component: [KeyBinding]) -> [KeyBinding] { component }
  public static func buildExpression(_ expression: KeyBinding) -> KeyBinding { expression }
}

public struct KeyBinding: Hashable, Sendable {
  public var chord: KeyChord
  public var command: Command?

  public init(_ chord: KeyChord, to command: Command?) {
    self.chord = chord
    self.command = command
  }
}

public func bind(_ key: Key, modifiers: KeyModifiers = [], to command: Command) -> KeyBinding {
  KeyBinding(KeyChord(key, modifiers: modifiers), to: command)
}

public func bind(_ character: Character, modifiers: KeyModifiers = [], to command: Command) -> KeyBinding {
  KeyBinding(KeyChord(character, modifiers: modifiers), to: command)
}

public func disable(_ key: Key, modifiers: KeyModifiers = []) -> KeyBinding {
  KeyBinding(KeyChord(key, modifiers: modifiers), to: nil)
}

public func disable(_ character: Character, modifiers: KeyModifiers = []) -> KeyBinding {
  KeyBinding(KeyChord(character, modifiers: modifiers), to: nil)
}

public struct KeyBindings: Sendable {
  private var entries: [KeyChord: Command?] = [:]

  public init(@KeyBindingsBuilder _ content: () -> [KeyBinding]) {
    for binding in content() { entries[binding.chord] = .some(binding.command) }
  }

  public init() {}

  public func command(for chord: KeyChord) -> Command?? { entries[chord] }

  /// Returns a keymap where bindings in `content` shadow this map.
  public func overlay(@KeyBindingsBuilder _ content: () -> [KeyBinding]) -> KeyBindings {
    var result = self
    for binding in content() { result.entries[binding.chord] = .some(binding.command) }
    return result
  }

  public func overlay(_ other: KeyBindings) -> KeyBindings {
    var result = self
    for (chord, command) in other.entries { result.entries[chord] = .some(command) }
    return result
  }

  public static let defaults = KeyBindings {
    bind(.upArrow, to: .navigation(.up))
    bind(.downArrow, to: .navigation(.down))
    bind(.leftArrow, to: .navigation(.left))
    bind(.rightArrow, to: .navigation(.right))
    bind(.tab, to: .navigation(.next))
    bind(.tab, modifiers: [.shift], to: .navigation(.previous))
    bind(.enter, to: .action(.activate))
    bind(.space, to: .action(.activate))
    bind(.escape, to: .action(.cancel))
    bind(.pageUp, to: .navigation(.pageUp))
    bind(.pageDown, to: .navigation(.pageDown))
    bind(.home, to: .navigation(.home))
    bind(.end, to: .navigation(.end))
  }
}
