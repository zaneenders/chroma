public enum InteractionPhase: Equatable, Sendable {
  case idle
  case hovered
  case pressed
}

public struct ButtonState: Equatable, Sendable {
  public var hovered: Bool
  public var held: Bool
  public var clicked: Bool

  public init(hovered: Bool, held: Bool, clicked: Bool) {
    self.hovered = hovered
    self.held = held
    self.clicked = clicked
  }

  public var phase: InteractionPhase {
    held ? .pressed : hovered ? .hovered : .idle
  }
}

public struct TextInputState: Equatable, Sendable {
  public var hovered: Bool
  public var held: Bool
  public var editing: Bool
  public var caretOffset: Int?
  public var selectionRange: Range<Int>?

  public init(
    hovered: Bool,
    held: Bool,
    editing: Bool,
    caretOffset: Int?,
    selectionRange: Range<Int>? = nil
  ) {
    self.hovered = hovered
    self.held = held
    self.editing = editing
    self.caretOffset = caretOffset
    self.selectionRange = selectionRange
  }

  public var phase: InteractionPhase {
    held ? .pressed : hovered ? .hovered : .idle
  }
}
