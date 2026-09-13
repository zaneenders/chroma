public enum Key: Hashable, Sendable {
  case character(Character)
  case upArrow, downArrow, leftArrow, rightArrow
  case tab, enter, escape, space
  case home, end, pageUp, pageDown
  case delete, backspace
}

public struct KeyModifiers: OptionSet, Hashable, Sendable, Codable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }

  public static let shift = Self(rawValue: 1 << 0)
  public static let control = Self(rawValue: 1 << 1)
  public static let option = Self(rawValue: 1 << 2)
  public static let command = Self(rawValue: 1 << 3)
  public static let superKey = Self(rawValue: 1 << 4)
}

public struct KeyChord: Hashable, Sendable, Codable {
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

  public func prefersTextInsertion(
    chord: KeyChord?, text: String?, isTextEditing: Bool
  ) -> Bool {
    guard isTextEditing, let text, !text.isEmpty else { return false }
    if let chord, let resolution = command(for: chord) {
      guard let command = resolution else { return false }
      if case .editing = command { return false }
    }
    return chord?.modifiers.intersection([.command, .control, .superKey]).isEmpty ?? true
  }

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
}

extension Key: Codable {
  private static var special: [Key] {
    [
      .upArrow, .downArrow, .leftArrow, .rightArrow, .tab, .enter, .escape,
      .space, .home, .end, .pageUp, .pageDown, .delete, .backspace,
    ]
  }
  public func encode(to encoder: any Encoder) throws {
    var values = encoder.unkeyedContainer()
    if case .character(let character) = self {
      try values.encode(-1)
      try values.encode(String(character))
    } else {
      try values.encode(Self.special.firstIndex(of: self)!)
    }
  }
  public init(from decoder: any Decoder) throws {
    var values = try decoder.unkeyedContainer()
    let tag = try values.decode(Int.self)
    if tag == -1 {
      let text = try values.decode(String.self)
      guard text.count == 1, let character = text.first else {
        throw DecodingError.dataCorruptedError(in: values, debugDescription: "Invalid character key")
      }
      self = .character(character)
    } else {
      guard Self.special.indices.contains(tag) else {
        throw DecodingError.dataCorruptedError(in: values, debugDescription: "Unknown key")
      }
      self = Self.special[tag]
    }
  }
}
