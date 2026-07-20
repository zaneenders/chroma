/// The immutable input snapshot for one frame.
///
/// Backends accumulate platform events between frames and hand the drained
/// result to ``Interaction/beginFrame(input:)`` at frame start, so a quick
/// press and release within one frame is never lost.
///
/// Held and edge-triggered state are distinct:
///
/// - `pointerDown`: held across frames
/// - `pointerPressed`: false-to-true transition during this frame
/// - `pointerReleased`: true-to-false transition during this frame
public struct InputState: Equatable, Sendable {
  /// Pointer position in pixel space (top-left origin), or a point outside
  /// the viewport when the pointer has left the window.
  public var pointerPosition: Point
  public var pointerDown: Bool
  public var pointerPressed: Bool
  public var pointerReleased: Bool
  public var scrollDelta: Point

  public init(
    pointerPosition: Point = .zero,
    pointerDown: Bool = false,
    pointerPressed: Bool = false,
    pointerReleased: Bool = false,
    scrollDelta: Point = .zero
  ) {
    self.pointerPosition = pointerPosition
    self.pointerDown = pointerDown
    self.pointerPressed = pointerPressed
    self.pointerReleased = pointerReleased
    self.scrollDelta = scrollDelta
  }
}
