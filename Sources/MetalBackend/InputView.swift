#if METAL_BACKEND

import AppKit
import Chroma
import MetalKit

final class ChromaInputView: MTKView {
  var interaction: Interaction!
  var keyBindings: KeyBindings = .defaults
  private var pointerPosition = Point(x: -1, y: -1)
  private var pointerPressPosition = Point(x: -1, y: -1)
  private var pointerDown = false
  private var pressedEdge = false
  private var releasedEdge = false
  private var scroll = Point.zero
  private var pendingCommands: [Command] = []
  private var pendingTextEvents: [TextEditEvent] = []

  func frameInput() -> InputState {
    let input = InputState(
      pointerPosition: pointerPosition,
      pointerPressPosition: pointerPressPosition,
      pointerDown: pointerDown,
      pointerPressed: pressedEdge,
      pointerReleased: releasedEdge,
      scrollDelta: scroll,
      semanticCommands: pendingCommands,
      textEvents: pendingTextEvents
    )
    pressedEdge = false
    releasedEdge = false
    pointerPressPosition = Point(x: -1, y: -1)
    scroll = .zero
    pendingCommands = []
    pendingTextEvents = []
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
    window?.makeFirstResponder(self)
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
    pointerPosition = Point(x: -1, y: -1)
  }

  override func scrollWheel(with event: NSEvent) {
    scroll.x += Float(event.scrollingDeltaX)
    scroll.y += Float(event.scrollingDeltaY)
  }

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    if event.modifierFlags.contains(.command),
      event.charactersIgnoringModifiers?.lowercased() == "c",
      let text = interaction.onCopy?(),
      !text.isEmpty
    {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      return
    }
    if interaction.isTextEditing {
      if event.modifierFlags.contains(.command),
        event.charactersIgnoringModifiers == "v",
        let pasted = NSPasteboard.general.string(forType: .string),
        !pasted.isEmpty
      {
        pendingTextEvents.append(.insert(pasted))
        return
      }
      if let edit = Self.textEditEvent(for: event) {
        pendingTextEvents.append(edit)
      } else {
        super.keyDown(with: event)
      }
      return
    }
    guard let chord = Self.keyChord(for: event) else {
      super.keyDown(with: event)
      return
    }
    // A disabled binding is still owned by the keymap and must not fall through.
    if let resolution = keyBindings.command(for: chord) {
      if let command = resolution { pendingCommands.append(command) }
    } else {
      super.keyDown(with: event)
    }
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

  private static func textEditEvent(for event: NSEvent) -> TextEditEvent? {
    switch event.keyCode {
    case 53: return .endEditing
    case 36, 76: return .submit
    case 51: return .backspace
    case 117: return .deleteForward
    case 123: return .moveCaretLeft
    case 124: return .moveCaretRight
    case 115: return .moveCaretToStart
    case 119: return .moveCaretToEnd
    default:
      guard event.modifierFlags.intersection([.command, .control]).isEmpty,
        let characters = event.characters,
        !characters.isEmpty,
        characters.utf8.allSatisfy({ $0 >= 0x20 && $0 != 0x7F })
      else { return nil }
      return .insert(characters)
    }
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

#endif
