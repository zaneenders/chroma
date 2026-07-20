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
  private var pointerDown = false
  private var pressedEdge = false
  private var releasedEdge = false
  private var scroll = Point.zero

  /// Drains the accumulated events into a frame snapshot. Edge-triggered
  /// fields and scroll deltas reset for the next frame.
  func frameInput() -> InputState {
    let input = InputState(
      pointerPosition: pointerPosition,
      pointerDown: pointerDown,
      pointerPressed: pressedEdge,
      pointerReleased: releasedEdge,
      scrollDelta: scroll
    )
    pressedEdge = false
    releasedEdge = false
    scroll = .zero
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
    updatePointer(with: event)
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
