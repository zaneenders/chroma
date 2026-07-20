#if METAL_BACKEND

import AppKit
import Chroma
import MetalKit

/// The Metal backend's rendering surface and input adapter.
///
/// AppKit delivers events more often than frames render, so events are
/// accumulated: edge-triggered state (press, release) and scroll deltas pile
/// up between frames, and ``frameInput()`` drains them into the frame's
/// immutable ``InputState`` snapshot. A quick press and release within one
/// frame therefore still produces exactly one click.
final class ChromaInputView: MTKView {
  private var pointerPosition = Point(x: -1, y: -1)
  private var pointerPressPosition = Point(x: -1, y: -1)
  private var pointerDown = false
  private var pressedEdge = false
  private var releasedEdge = false
  private var scroll = Point.zero
  /// Keyboard input accumulated between frames, already translated into the
  /// framework's input language by ``keyDown(with:)``.
  private var pendingCommands: [UICommand] = []

  /// Drains the accumulated events into a frame snapshot. Edge-triggered
  /// fields, scroll deltas, and queued commands reset for the next frame.
  func frameInput() -> InputState {
    let input = InputState(
      pointerPosition: pointerPosition,
      pointerPressPosition: pointerPressPosition,
      pointerDown: pointerDown,
      pointerPressed: pressedEdge,
      pointerReleased: releasedEdge,
      scrollDelta: scroll,
      commands: pendingCommands
    )
    pressedEdge = false
    releasedEdge = false
    pointerPressPosition = Point(x: -1, y: -1)
    scroll = .zero
    pendingCommands = []
    return input
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
        owner: self,
        userInfo: nil
      )
    )
  }

  override func mouseMoved(with event: NSEvent) {
    updatePointer(with: event)
  }

  override func mouseDragged(with event: NSEvent) {
    updatePointer(with: event)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)  // Clicks focus the view for keyboard.
    updatePointer(with: event)
    pointerPressPosition = pointerPosition
    pointerDown = true
    pressedEdge = true
  }

  override func mouseUp(with event: NSEvent) {
    updatePointer(with: event)
    pointerDown = false
    releasedEdge = true
  }

  override func mouseExited(with event: NSEvent) {
    // Outside the window nothing is hovered; hit-testing uses `<` on the
    // max edges, so a negative position is never inside a rect.
    pointerPosition = Point(x: -1, y: -1)
  }

  override func scrollWheel(with event: NSEvent) {
    scroll.x += Float(event.scrollingDeltaX)
    scroll.y += Float(event.scrollingDeltaY)
  }

  // MARK: Keyboard

  override var acceptsFirstResponder: Bool { true }

  /// The keymap: the only device-specific piece of input. Keys compile
  /// directly into the framework's input language — mirrored home-row pairs
  /// (`d`/`f` left hand, `j`/`k` right hand) for the four directions, `l`
  /// to step in, `s` to step out, and return or space to activate. Arrow
  /// keys are aliases for the directions. Held keys repeat via AppKit's key
  /// repeat, which is exactly repeated movement.
  override func keyDown(with event: NSEvent) {
    let command: UICommand?
    switch event.keyCode {
    case 123: command = .left
    case 124: command = .right
    case 125: command = .down
    case 126: command = .up
    case 36, 76, 49: command = .activate  // return, keypad enter, space
    default:
      if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
        switch event.charactersIgnoringModifiers {
        case "l": command = .in
        case "s": command = .out
        case "j": command = .down
        case "f": command = .up
        case "k": command = .right
        case "d": command = .left
        default: command = nil
        }
      } else {
        command = nil  // Modified keys belong to the system, not navigation.
      }
    }
    if let command {
      pendingCommands.append(command)
    } else {
      super.keyDown(with: event)
    }
  }

  /// Converts AppKit view points (bottom-left origin, in points) into Chroma
  /// pixel space (top-left origin, drawable pixels).
  private func updatePointer(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    guard bounds.width > 0, bounds.height > 0, drawableSize.width > 0 else { return }
    let scaleX = drawableSize.width / bounds.width
    let scaleY = drawableSize.height / bounds.height
    pointerPosition = Point(
      x: Float(location.x * scaleX),
      y: Float((bounds.height - location.y) * scaleY)
    )
  }
}

#endif
