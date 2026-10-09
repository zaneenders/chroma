import Chroma
import Foundation

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

  private var fingerScrolling = false
  private var horizontalMomentum = ScrollMomentum()
  private var verticalMomentum = ScrollMomentum()

  var hasScrollMomentum: Bool { horizontalMomentum.isActive || verticalMomentum.isActive }

  func scrollSource(isFinger: Bool, hasMovement: Bool = false) {
    if !isFinger
      || (hasMovement && hasScrollMomentum && !horizontalMomentum.isTracking && !verticalMomentum.isTracking)
    {
      cancelMomentum()
    }
    fingerScrolling = isFinger
  }

  private func cancelMomentum() {
    horizontalMomentum.cancel()
    verticalMomentum.cancel()
  }

  func stopScroll(horizontal: Bool, time: UInt32, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    guard fingerScrolling else { return }
    if horizontal {
      horizontalMomentum.stop(time: time, now: now)
    } else {
      verticalMomentum.stop(time: time, now: now)
    }
  }

  func frameInput(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> InputState {
    scroll.x += horizontalMomentum.advance(now: now)
    scroll.y += verticalMomentum.advance(now: now)
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

  func reset() {
    pointerPosition = Point(x: -1, y: -1)
    pointerPressPosition = pointerPosition
    pointerDown = false
    pressedEdge = false
    releasedEdge = false
    scroll = .zero
    commands.removeAll(keepingCapacity: true)
    textEvents.removeAll(keepingCapacity: true)
    fingerScrolling = false
    cancelMomentum()
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
    cancelMomentum()
    fingerScrolling = false
    pointerPosition = Point(x: -1, y: -1)
  }

  func pointerPressed() {
    cancelMomentum()
    pointerPressPosition = pointerPosition
    pointerDown = true
    pressedEdge = true
  }

  func pointerReleased() {
    pointerDown = false
    releasedEdge = true
  }

  func scrollBy(horizontal: Bool, delta: Float, time: UInt32) {
    if fingerScrolling {
      if horizontal {
        horizontalMomentum.record(delta: delta, time: time)
      } else {
        verticalMomentum.record(delta: delta, time: time)
      }
    } else {
      cancelMomentum()
    }
    if horizontal { scroll.x += delta } else { scroll.y += delta }
  }
}
