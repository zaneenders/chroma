import Chroma
import Foundation

@MainActor
final class InputAccumulator {
  private var pointerPosition = Point(x: -1, y: -1)
  private var pointerPressPosition = Point(x: -1, y: -1)
  private var pointerDown = false
  private var events: [InputState] = []

  private var fingerScrolling = false
  private var horizontalMomentum = ScrollMomentum()
  private var verticalMomentum = ScrollMomentum()

  var hasScrollMomentum: Bool { horizontalMomentum.isActive || verticalMomentum.isActive }

  func scrollSource(isFinger: Bool) {
    if !isFinger { cancelMomentum() }
    fingerScrolling = isFinger
  }

  private func cancelMomentum() {
    horizontalMomentum.cancel()
    verticalMomentum.cancel()
  }

  func stopScroll(horizontal: Bool, time: UInt32) {
    guard fingerScrolling else { return }
    let now = ProcessInfo.processInfo.systemUptime
    if horizontal {
      horizontalMomentum.stop(time: time, now: now)
    } else {
      verticalMomentum.stop(time: time, now: now)
    }
  }

  private func snapshot(
    pressed: Bool = false, released: Bool = false, scroll: Point = .zero,
    commands: [Command] = [], textEvents: [TextEditEvent] = []
  ) -> InputState {
    InputState(
      pointerPosition: pointerPosition, pointerPressPosition: pointerPressPosition,
      pointerDown: pointerDown, pointerPressed: pressed, pointerReleased: released,
      scrollDelta: scroll, commands: commands, textEvents: textEvents)
  }

  func drain() -> [InputState] {
    let now = ProcessInfo.processInfo.systemUptime
    let momentum = Point(
      x: horizontalMomentum.advance(now: now), y: verticalMomentum.advance(now: now))
    if momentum != .zero { events.append(snapshot(scroll: momentum)) }
    let result = events
    events.removeAll(keepingCapacity: true)
    return result
  }

  func drainKeyboard(_ keyboard: WaylandKeyboard, editingSession: Int) {
    keyboard.drain(editingSession: editingSession) { input in
      events.append(snapshot(commands: input.commands, textEvents: input.textEvents))
    }
  }

  var pointerPositionSnapshot: Point { pointerPosition }

  func pointerEntered(x: Float, y: Float) {
    pointerPosition = Point(x: x, y: y)
    events.append(snapshot())
  }

  func pointerMoved(x: Float, y: Float) {
    pointerPosition = Point(x: x, y: y)
    events.append(snapshot())
  }

  func pointerLeft() {
    cancelMomentum()
    fingerScrolling = false
    pointerPosition = Point(x: -1, y: -1)
    events.append(snapshot())
  }

  func pointerPressed() {
    cancelMomentum()
    pointerPressPosition = pointerPosition
    pointerDown = true
    events.append(snapshot(pressed: true))
  }

  func pointerReleased() {
    pointerDown = false
    events.append(snapshot(released: true))
  }

  func scrollBy(x: Float, y: Float, time: UInt32) {
    if fingerScrolling {
      if x != 0 { horizontalMomentum.record(delta: x, time: time) }
      if y != 0 { verticalMomentum.record(delta: y, time: time) }
    } else {
      cancelMomentum()
    }
    events.append(snapshot(scroll: Point(x: x, y: y)))
  }
}
