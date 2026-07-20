/// The immutable input snapshot for one frame.
///
/// Backends accumulate platform events between frames and hand the drained
/// result to ``Interaction/beginFrame(input:)`` at frame start, so a quick
/// press and release within one frame is never lost.
///
/// Keyboards don't deliver key codes here: the backend translates them into
/// the framework's input language and enqueues ``commands`` — pointer motion
/// is compiled into the same language by ``Interaction`` itself (see the
/// `UICommand` docs for the model).
///
/// Held and edge-triggered state are distinct:
///
/// - `pointerDown`: held across frames
/// - `pointerPressed`: false-to-true transition during this frame
/// - `pointerReleased`: true-to-false transition during this frame
/// - `pointerPressPosition`: the pointer location at the moment of the most
///   recent press, used to establish capture on the correct widget even when
///   the pointer moves before the next rendered frame.
public struct InputState: Equatable, Sendable {
  /// Pointer position in pixel space (top-left origin), or a point outside
  /// the viewport when the pointer has left the window.
  public var pointerPosition: Point
  /// The position at which the most recent press occurred (or a sentinel
  /// outside the viewport when no press happened this frame).
  public var pointerPressPosition: Point
  public var pointerDown: Bool
  public var pointerPressed: Bool
  public var pointerReleased: Bool
  public var scrollDelta: Point
  /// The keyboard's contribution for this frame, already translated into
  /// the input language by the backend's keymap. Applied after any pointer
  /// macros, so the keyboard speaks last within a frame.
  public var commands: [UICommand]
  /// Editing-mode input for this frame. While a text field owns the
  /// keyboard (``Interaction/isTextEditing``), the backend translates keys
  /// into these instead of ``commands``; the editing field drains them
  /// during draw.
  public var textEvents: [TextEditEvent]

  public init(
    pointerPosition: Point = .zero,
    pointerPressPosition: Point = Point(x: -1, y: -1),
    pointerDown: Bool = false,
    pointerPressed: Bool = false,
    pointerReleased: Bool = false,
    scrollDelta: Point = .zero,
    commands: [UICommand] = [],
    textEvents: [TextEditEvent] = []
  ) {
    self.pointerPosition = pointerPosition
    self.pointerPressPosition = pointerPressPosition
    self.pointerDown = pointerDown
    self.pointerPressed = pointerPressed
    self.pointerReleased = pointerReleased
    self.scrollDelta = scrollDelta
    self.commands = commands
    self.textEvents = textEvents
  }
}
