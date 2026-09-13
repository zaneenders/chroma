import Chroma

@MainActor
final class InputAccumulator {
  private var pointerPosition = Point(x: -1, y: -1)
  private var pointerPressPosition = Point(x: -1, y: -1)
  private var pointerDown = false
  private var pressedEdge = false
  private var releasedEdge = false
  private var scroll = Point.zero
  private var commands: [Command] = []
  private var textEvents: [TextEditEvent] = []

  func frameInput() -> InputState {
    let input = InputState(
      pointerPosition: pointerPosition,
      pointerPressPosition: pointerPressPosition,
      pointerDown: pointerDown,
      pointerPressed: pressedEdge,
      pointerReleased: releasedEdge,
      scrollDelta: scroll,
      commands: commands,
      textEvents: textEvents
    )
    pressedEdge = false
    releasedEdge = false
    pointerPressPosition = Point(x: -1, y: -1)
    scroll = .zero
    commands.removeAll(keepingCapacity: true)
    textEvents.removeAll(keepingCapacity: true)
    return input
  }

  func drainKeyboard(_ keyboard: WaylandKeyboard, editingSession: Int) {
    keyboard.drain(
      editingSession: editingSession, commands: &commands, textEvents: &textEvents)
  }

  var pointerPositionSnapshot: Point { pointerPosition }

  func pointerEntered(x: Float, y: Float) {
    pointerPosition = Point(x: x, y: y)
  }

  func pointerMoved(x: Float, y: Float) {
    pointerPosition = Point(x: x, y: y)
  }

  func pointerLeft() {
    pointerPosition = Point(x: -1, y: -1)
  }

  func pointerPressed() {
    pointerPressPosition = pointerPosition
    pointerDown = true
    pressedEdge = true
  }

  func pointerReleased() {
    pointerDown = false
    releasedEdge = true
  }

  func scrollBy(x: Float, y: Float) {
    scroll.x += x
    scroll.y += y
  }
}
