public struct KeyboardInput: Equatable, Sendable {
  public var chord: KeyChord?
  public var text: String?

  public init(chord: KeyChord? = nil, text: String? = nil) {
    self.chord = chord
    self.text = text
  }
}

public enum ResolvedKeyboardInput: Equatable, Sendable {
  case command(Command)
  case text(TextEditEvent)
}
