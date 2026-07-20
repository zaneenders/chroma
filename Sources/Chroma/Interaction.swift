/// The ambient per-frame interaction context: the input snapshot plus the
/// retained state immediate-mode widgets need (`hot` / `active`), owned and
/// pumped by the rendering backend.
///
/// Blocks are re-evaluated value types with no storage of their own, so
/// interaction state lives here, ImGui-style: the backend installs its
/// context as ``current`` and calls ``beginFrame(input:)`` once per frame;
/// interactive primitives read and update it during their draw.
///
/// ## Hit-testing with overlapping widgets
///
/// Widgets are drawn back-to-front (e.g. ZStack children in order).  Because
/// later widgets paint on top they must also win hit-tests.  ``hot`` is
/// therefore resolved one frame behind: during draw each hoverable widget
/// records itself as `hot` (last writer wins = top-most), and
/// ``beginFrame(input:)`` snapshots that value into `resolvedHot` for the
/// current frame's hover gating.  This allows ``ButtonState/hovered`` to
/// return `true` for only one widget once the pointer settles.
///
/// Press capture is gated on `resolvedHot` so that the top-most widget
/// captures the press even when other widgets overlap it.
@MainActor
public final class Interaction {
  /// The context blocks interact with. Backends replace this with their own
  /// instance at startup; until multi-window support arrives there is exactly
  /// one context per process.
  public static var current = Interaction()

  /// The current frame's input snapshot.
  public private(set) var input = InputState()

  /// The top-most widget under the pointer this frame, claimed during draw.
  /// Updated by each hoverable widget so the last (top-most) writer wins.
  public private(set) var hot: WidgetID?

  /// The widget that captured the press and is waiting for release.
  public private(set) var active: WidgetID?

  /// The previous frame's ``hot``, resolved at the start of this frame.
  /// Used to gate hover so only one overlapping widget reports
  /// `hovered == true`, and to gate press capture so the top-most widget
  /// wins.  Nil on the first frame or after a release clears state.
  private var resolvedHot: WidgetID?

  /// Smoothed frames per second, maintained by the backend.
  public var frameRate: Double = 0

  public init() {}

  /// Installs the frame's input snapshot and snapshots the previous frame's
  /// ``hot`` into `resolvedHot`.  Backends call this once per frame before
  /// drawing; interactive primitives read `resolvedHot` and update ``hot``
  /// during their draw.
  public func beginFrame(input: InputState) {
    self.input = input
    resolvedHot = hot
    hot = nil
  }

  /// Finalizes the interaction frame. Backends call this once per frame
  /// after drawing; clears any active capture if the pointer was released
  /// this frame but no widget claimed the release (e.g. the active widget
  /// disappeared while held).
  public func endFrame() {
    if input.pointerReleased {
      active = nil
      hot = nil
    }
  }

  /// Shared press and capture semantics for button-like widgets, evaluated
  /// against the widget's assigned rect during its draw:
  ///
  /// - the widget is hovered when the pointer is inside, not captured by
  ///   another widget, and either `resolvedHot` points to this widget or
  ///   no widget has claimed hover yet this frame,
  /// - a press inside captures the pointer (`active`), gated by
  ///   `resolvedHot` so the top-most overlapping widget wins,
  /// - a release inside while captured clicks; a release anywhere just
  ///   clears the capture — so press-inside-release-outside never clicks.
  public func buttonBehavior(id: WidgetID, rect: Rect) -> ButtonState {
    let inside = rect.contains(input.pointerPosition)
    let hoverable = active == nil || active == id

    // Only one widget per frame reports hovered: the one matching the
    // resolved `resolvedHot` (top-most from the previous frame), or the
    // first hoverable widget when resolvedHot is nil (first frame / after
    // release).  Active widgets bypass the gate so they re-hover on
    // drag-return.
    let hovered = inside && hoverable
      && (resolvedHot == nil || resolvedHot == id || active == id)
    if inside && hoverable { hot = id }

    // Capture is established using the press position so that a press
    // that starts outside the widget never captures it, even when the
    // pointer is dragged inside before the next rendered frame.
    // The `resolvedHot` gate ensures the top-most overlapping widget wins.
    let pressPos = input.pointerPressPosition
    let pressInside = rect.contains(pressPos.x >= 0 ? pressPos : input.pointerPosition)
    let canCapture =
      (active == nil && (resolvedHot == nil || resolvedHot == id)) || active == id
    let pressedInside = input.pointerPressed && pressInside && canCapture
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
