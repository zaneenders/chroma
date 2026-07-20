#if WAYLAND_BACKEND

import Chroma

/// Accumulates Wayland pointer events between frames, mirroring the Metal
/// backend's ``ChromaInputView/frameInput()`` semantics.
///
/// Edge-triggered state (press, release) and scroll deltas pile up between
/// frames; ``frameInput()`` drains them into the frame's immutable
/// ``InputState`` snapshot.
@MainActor
final class InputAccumulator {
  private var pointerPosition = Point(x: -1, y: -1)
  private var pointerPressPosition = Point(x: -1, y: -1)
  private var pointerDown = false
  private var pressedEdge = false
  private var releasedEdge = false
  private var scroll = Point.zero

  /// Drains accumulated events into a frame snapshot. Edge-triggered fields
  /// and scroll deltas reset for the next frame.
  func frameInput() -> InputState {
    let input = InputState(
      pointerPosition: pointerPosition,
      pointerPressPosition: pointerPressPosition,
      pointerDown: pointerDown,
      pointerPressed: pressedEdge,
      pointerReleased: releasedEdge,
      scrollDelta: scroll
    )
    pressedEdge = false
    releasedEdge = false
    pointerPressPosition = Point(x: -1, y: -1)
    scroll = .zero
    return input
  }

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

#endif
