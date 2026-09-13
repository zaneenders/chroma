import AppKit
import Chroma
import MetalKit

public final class ChromaInputView: MTKView {
  public var onRemoteKey: ((KeyChord?, String?) -> Void)?
  public var onInputAvailable: (() -> Void)?
  private var pointerPosition = Point(x: -1, y: -1)
  private var pointerPressPosition = Point(x: -1, y: -1)
  private var pointerDown = false
  private var pressedEdge = false
  private var releasedEdge = false
  private var scroll = Point.zero

  public func frameInput() -> InputState {
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

  private func scheduleRedraw() {
    needsDisplay = true
    onInputAvailable?()
  }

  public override func updateTrackingAreas() {
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

  public override func mouseMoved(with event: NSEvent) {
    updatePointer(with: event)
    scheduleRedraw()
  }

  public override func mouseDragged(with event: NSEvent) {
    updatePointer(with: event)
    scheduleRedraw()
  }

  public override func mouseDown(with event: NSEvent) {
    unsafe window?.makeFirstResponder(self)
    updatePointer(with: event)
    pointerPressPosition = pointerPosition
    pointerDown = true
    pressedEdge = true
    scheduleRedraw()
  }

  public override func mouseUp(with event: NSEvent) {
    updatePointer(with: event)
    pointerDown = false
    releasedEdge = true
    scheduleRedraw()
  }

  public override func mouseExited(with event: NSEvent) {
    pointerPosition = Point(x: -1, y: -1)
    scheduleRedraw()
  }

  public override func scrollWheel(with event: NSEvent) {
    scroll.x += Float(event.scrollingDeltaX)
    scroll.y += Float(event.scrollingDeltaY)
    scheduleRedraw()
  }

  public override var acceptsFirstResponder: Bool { true }

  public override func keyDown(with event: NSEvent) {
    if let onRemoteKey {
      let text: String?
      if case .insert(let value) = Self.textInsertionEvent(for: event) { text = value } else { text = nil }
      onRemoteKey(Self.keyChord(for: event), text)
      return
    }
    super.keyDown(with: event)
  }

  private static func keyChord(for event: NSEvent) -> KeyChord? {
    let key: Key
    switch event.keyCode {
    case 48: key = .tab
    case 123: key = .leftArrow
    case 124: key = .rightArrow
    case 125: key = .downArrow
    case 126: key = .upArrow
    case 116: key = .pageUp
    case 121: key = .pageDown
    case 115: key = .home
    case 119: key = .end
    case 36, 76: key = .enter
    case 49: key = .space
    case 53: key = .escape
    case 51: key = .backspace
    case 117: key = .delete
    default:
      guard let value = event.charactersIgnoringModifiers?.lowercased(), value.count == 1,
        let character = value.first
      else { return nil }
      key = .character(character)
    }
    var modifiers: KeyModifiers = []
    if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
    if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
    if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
    if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
    return KeyChord(key, modifiers: modifiers)
  }

  private static func textInsertionEvent(for event: NSEvent) -> TextEditEvent? {
    guard event.modifierFlags.intersection([.command, .control]).isEmpty,
      let characters = event.characters,
      !characters.isEmpty,
      characters.utf8.allSatisfy({ $0 >= 0x20 && $0 != 0x7F })
    else { return nil }
    return .insert(characters)
  }

  private func updatePointer(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    guard bounds.width > 0, bounds.height > 0 else { return }
    pointerPosition = Point(
      x: Float(location.x),
      y: Float(bounds.height - location.y)
    )
  }
}
