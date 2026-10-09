public struct InputState: Equatable, Sendable {
  public var pointerPosition: Point
  public var pointerPressPosition: Point
  public var pointerDown: Bool
  public var pointerPressed: Bool
  public var pointerReleased: Bool
  public var scrollDelta: Point
  public var commands: [Command]
  public var textEvents: [TextEditEvent]

  var isActionable: Bool {
    pointerDown || pointerPressed || pointerReleased || scrollDelta != .zero
      || !commands.isEmpty || !textEvents.isEmpty
  }

  package var settled: InputState {
    var copy = self
    copy.pointerPressed = false
    copy.pointerReleased = false
    copy.scrollDelta = .zero
    copy.commands = []
    copy.textEvents = []
    return copy
  }

  public init(
    pointerPosition: Point = .zero,
    pointerPressPosition: Point? = nil,
    pointerDown: Bool = false,
    pointerPressed: Bool = false,
    pointerReleased: Bool = false,
    scrollDelta: Point = .zero,
    commands: [Command] = [],
    textEvents: [TextEditEvent] = []
  ) {
    self.pointerPosition = pointerPosition
    self.pointerPressPosition = pointerPressPosition ?? pointerPosition
    self.pointerDown = pointerDown
    self.pointerPressed = pointerPressed
    self.pointerReleased = pointerReleased
    self.scrollDelta = scrollDelta
    self.commands = commands
    self.textEvents = textEvents
  }
}
