/// The ambient per-frame interaction context: the input snapshot plus the
/// retained state immediate-mode widgets need (`hot` / `active`), owned and
/// pumped by the rendering backend.
///
/// Blocks are re-evaluated value types with no storage of their own, so
/// interaction state lives here, ImGui-style: the backend installs its
/// context as ``current`` and calls ``beginFrame(input:)`` once per frame;
/// interactive primitives read and update it during their draw.
@MainActor
public final class Interaction {
  /// The context blocks interact with. Backends replace this with their own
  /// instance at startup; until multi-window support arrives there is exactly
  /// one context per process.
  public static var current = Interaction()

  /// The current frame's input snapshot.
  public private(set) var input = InputState()

  /// The widget under the pointer this frame, claimed during draw.
  public private(set) var hot: WidgetID?

  /// The widget that captured the press and is waiting for release.
  public private(set) var active: WidgetID?

  /// Smoothed frames per second, maintained by the backend.
  public var frameRate: Double = 0

  public init() {}

  /// Installs the frame's input snapshot. Backends call this once per frame
  /// before drawing; widgets re-claim ``hot`` during their draw.
  public func beginFrame(input: InputState) {
    self.input = input
    hot = nil
  }

  /// Finalizes the interaction frame. Backends call this once per frame
  /// after drawing; clears any active capture if the pointer was released
  /// this frame but no widget claimed the release (e.g. the active widget
  /// disappeared while held).
  public func endFrame() {
    if input.pointerReleased {
      active = nil
    }
  }

  /// Shared press and capture semantics for button-like widgets, evaluated
  /// against the widget's assigned rect during its draw:
  ///
  /// - the widget is hovered when the pointer is inside and not captured by
  ///   another widget,
  /// - a press inside captures the pointer (`active`),
  /// - a release inside while captured clicks; a release anywhere just
  ///   clears the capture — so press-inside-release-outside never clicks.
  public func buttonBehavior(id: WidgetID, rect: Rect) -> ButtonState {
    let hovered = rect.contains(input.pointerPosition) && (active == nil || active == id)
    if hovered { hot = id }

    // Capture is established using the press position so that a press
    // that starts outside the widget never captures it, even when the
    // pointer is dragged inside before the next rendered frame.
    let pressPos = input.pointerPressPosition
    let pressedInside = input.pointerPressed
      && rect.contains(pressPos.x >= 0 ? pressPos : input.pointerPosition)
      && active == nil
    if pressedInside { active = id }

    let clicked = active == id && hovered && input.pointerReleased
    if active == id && input.pointerReleased { active = nil }
    return ButtonState(
      hovered: hovered,
      held: active == id && input.pointerDown,
      clicked: clicked
    )
  }
}

/// How a widget currently interacts with the pointer.
public enum InteractionPhase: Equatable, Sendable {
  case idle
  case hovered
  case pressed
}

/// The result of evaluating press interaction for one widget this frame.
public struct ButtonState: Equatable, Sendable {
  /// The pointer is over the widget.
  public var hovered: Bool
  /// The widget captured the press and the button is still down.
  public var held: Bool
  /// The press completed inside the widget this frame.
  public var clicked: Bool

  public init(hovered: Bool, held: Bool, clicked: Bool) {
    self.hovered = hovered
    self.held = held
    self.clicked = clicked
  }

  /// The phase used for styling this frame.
  public var phase: InteractionPhase {
    held ? .pressed : hovered ? .hovered : .idle
  }
}
