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
  public static let superKey = Self(rawValue: 1 << 4)
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

public enum KeyBindingContext: Hashable, Sendable {
  case shared
  case movement
  case editing
}

public struct KeyBinding: Hashable, Sendable {
  public var chord: KeyChord
  public var context: KeyBindingContext
  public var command: Command?

  public init(_ chord: KeyChord, in context: KeyBindingContext? = nil, to command: Command?) {
    self.chord = chord
    self.context = context ?? Self.defaultContext(for: command)
    self.command = command
  }

  private static func defaultContext(for command: Command?) -> KeyBindingContext {
    guard let command else { return .shared }
    return switch command {
    case .navigation: .movement
    case .editing: .editing
    case .action, .application: .shared
    }
  }
}

public func bind(
  _ key: Key, modifiers: KeyModifiers = [], in context: KeyBindingContext? = nil, to command: Command
) -> KeyBinding {
  KeyBinding(KeyChord(key, modifiers: modifiers), in: context, to: command)
}

public func bind(
  _ character: Character, modifiers: KeyModifiers = [], in context: KeyBindingContext? = nil, to command: Command
) -> KeyBinding {
  KeyBinding(KeyChord(character, modifiers: modifiers), in: context, to: command)
}

public func disable(
  _ key: Key, modifiers: KeyModifiers = [], in context: KeyBindingContext = .shared
) -> KeyBinding {
  KeyBinding(KeyChord(key, modifiers: modifiers), in: context, to: nil)
}

public func disable(
  _ character: Character, modifiers: KeyModifiers = [], in context: KeyBindingContext = .shared
) -> KeyBinding {
  KeyBinding(KeyChord(character, modifiers: modifiers), in: context, to: nil)
}

public struct KeyBindings: Sendable {
  private var entries: [KeyChord: [KeyBindingContext: Command?]] = [:]

  public init(@KeyBindingsBuilder _ content: () -> [KeyBinding]) {
    for binding in content() { entries[binding.chord, default: [:]][binding.context] = binding.command }
  }

  public init() {}

  public func command(for chord: KeyChord) -> Command?? {
    for context in [.editing, .movement, .shared] as [KeyBindingContext] {
      if let command = entries[chord]?[context] { return .some(command) }
    }
    return nil
  }

  public func command(for chord: KeyChord, isTextEditing: Bool) -> Command?? {
    let contexts: [KeyBindingContext] = isTextEditing ? [.editing, .shared] : [.movement, .shared]
    for context in contexts {
      if let command = entries[chord]?[context] { return .some(command) }
    }
    return nil
  }

  public func resolve(_ input: KeyboardInput, isTextEditing: Bool) -> ResolvedKeyboardInput? {
    resolve(input, isTextEditing: isTextEditing) { chord in
      command(for: chord, isTextEditing: isTextEditing)
    }
  }

  package func resolve(
    _ input: KeyboardInput,
    isTextEditing: Bool,
    commandForChord: (KeyChord) -> Command??
  ) -> ResolvedKeyboardInput? {
    if isTextEditing, let text = input.text, !text.isEmpty {
      if let chord = input.chord, let resolution = commandForChord(chord) {
        if resolution == nil { return nil }
      } else if input.chord?.modifiers.intersection([.command, .control, .superKey]).isEmpty ?? true {
        return .text(.insert(text))
      }
    }
    guard let chord = input.chord,
      let resolution = commandForChord(chord),
      let command = resolution
    else { return nil }
    return switch command {
    case .editing(let event): .text(event)
    default: .command(command)
    }
  }

  public func prefersTextInsertion(
    chord: KeyChord?, text: String?, isTextEditing: Bool
  ) -> Bool {
    if case .some(.text(.insert)) = resolve(KeyboardInput(chord: chord, text: text), isTextEditing: isTextEditing) {
      return true
    }
    return false
  }

  public func overlay(@KeyBindingsBuilder _ content: () -> [KeyBinding]) -> KeyBindings {
    var result = self
    for binding in content() { result.entries[binding.chord, default: [:]][binding.context] = binding.command }
    return result
  }

  public func overlay(_ other: KeyBindings) -> KeyBindings {
    var result = self
    for (chord, bindings) in other.entries {
      for (context, command) in bindings { result.entries[chord, default: [:]][context] = command }
    }
    return result
  }
}

extension KeyBindings {
  public static let vimNavigation = KeyBindings {
    bind("f", to: .navigation(.up))
    bind(.upArrow, to: .navigation(.up))
    bind("j", to: .navigation(.down))
    bind(.downArrow, to: .navigation(.down))
    bind("d", to: .navigation(.left))
    bind(.leftArrow, to: .navigation(.left))
    bind("k", to: .navigation(.right))
    bind(.rightArrow, to: .navigation(.right))
    bind(.enter, in: .movement, to: .action(.activate))
    bind(.space, in: .movement, to: .action(.activate))
    bind(.escape, to: .action(.cancel))
  }
}
