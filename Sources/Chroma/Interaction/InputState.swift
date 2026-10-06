public struct InputState: Equatable, Sendable {
  public var pointerPosition: Point
  public var pointerPressPosition: Point
  public var pointerDown: Bool
  public var pointerPressed: Bool
  public var pointerReleased: Bool
  public var scrollDelta: Point
  public var commands: [Command]
  public var textEvents: [TextEditEvent]

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

extension InputState {
  var separateEvents: [InputState] {
    guard commands.count + textEvents.count > 1 else { return [self] }
    var state = self
    state.commands = []
    state.textEvents = []
    var events: [InputState] = []
    for command in commands {
      state.commands = [command]
      events.append(state)
      state.pointerPressed = false
      state.pointerReleased = false
      state.scrollDelta = .zero
    }
    state.commands = []
    for event in textEvents {
      state.textEvents = [event]
      events.append(state)
      state.pointerPressed = false
      state.pointerReleased = false
      state.scrollDelta = .zero
    }
    return events
  }
}
