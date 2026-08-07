public struct InputState: Equatable, Sendable {
  public var pointerPosition: Point
  public var pointerPressPosition: Point
  public var pointerDown: Bool
  public var pointerPressed: Bool
  public var pointerReleased: Bool
  public var scrollDelta: Point
  public var commands: [UICommand]
  public var semanticCommands: [Command]
  public var textEvents: [TextEditEvent]

  public init(
    pointerPosition: Point = .zero,
    pointerPressPosition: Point = Point(x: -1, y: -1),
    pointerDown: Bool = false,
    pointerPressed: Bool = false,
    pointerReleased: Bool = false,
    scrollDelta: Point = .zero,
    commands: [UICommand] = [],
    semanticCommands: [Command] = [],
    textEvents: [TextEditEvent] = []
  ) {
    self.pointerPosition = pointerPosition
    self.pointerPressPosition = pointerPressPosition
    self.pointerDown = pointerDown
    self.pointerPressed = pointerPressed
    self.pointerReleased = pointerReleased
    self.scrollDelta = scrollDelta
    self.commands = commands
    self.semanticCommands = semanticCommands + commands.map(\.command)
    self.textEvents = textEvents
  }
}
