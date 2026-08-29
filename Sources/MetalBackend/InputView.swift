#if METAL_BACKEND

import AppKit
import Chroma
import MetalKit

final class ChromaInputView: MTKView {
  var interaction: Interaction!
  var keyBindings = KeyBindings()
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
      commands: pendingCommands,
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

  private func scheduleRedraw() {
    needsDisplay = true
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
    scheduleRedraw()
  }

  override func mouseDragged(with event: NSEvent) {
    updatePointer(with: event)
    scheduleRedraw()
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    updatePointer(with: event)
    pointerPressPosition = pointerPosition
    pointerDown = true
    pressedEdge = true
    scheduleRedraw()
  }

  override func mouseUp(with event: NSEvent) {
    updatePointer(with: event)
    pointerDown = false
    releasedEdge = true
    scheduleRedraw()
  }

  override func mouseExited(with event: NSEvent) {
    pointerPosition = Point(x: -1, y: -1)
    scheduleRedraw()
  }

  override func scrollWheel(with event: NSEvent) {
    scroll.x += Float(event.scrollingDeltaX)
    scroll.y += Float(event.scrollingDeltaY)
    scheduleRedraw()
  }

  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    scheduleRedraw()
    guard let chord = Self.keyChord(for: event) else {
      if interaction.mode == .editing, let edit = Self.textInsertionEvent(for: event) {
        pendingTextEvents.append(edit)
      } else {
        super.keyDown(with: event)
      }
      return
    }
    let resolution = keyBindings.command(for: chord)
    if interaction.mode == .editing {
      // Editing commands are explicit. Movement-mode commands on printable keys are ignored
      // here so bindings such as Space-to-activate and j-to-move still insert text while editing.
      if case .some(.some(let command)) = resolution,
        case .editing = command,
        handlePlatformCommand(command)
      {
        return
      }
      if case .some(.none) = resolution { return }
      if let edit = Self.textInsertionEvent(for: event) {
        pendingTextEvents.append(edit)
        return
      }
    }
    // A disabled binding is still owned by the keymap and must not fall through.
    if let resolution {
      guard let command = resolution else { return }
      if handlePlatformCommand(command) { return }
      pendingCommands.append(command)
    } else {
      super.keyDown(with: event)
    }
  }

  private func handlePlatformCommand(_ command: Command) -> Bool {
    guard case .editing(let editing) = command else { return false }
    switch editing {
    case .insert(let text):
      guard interaction.mode == .editing else { return true }
      pendingTextEvents.append(.insert(text))
    case .copy:
      guard let text = interaction.copyText(), !text.isEmpty else { return true }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    case .cut:
      guard interaction.mode == .editing,
        let text = interaction.copyText(), !text.isEmpty
      else { return true }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      pendingTextEvents.append(.deleteForward)
    case .paste:
      guard interaction.mode == .editing,
        let pasted = NSPasteboard.general.string(forType: .string),
        !pasted.isEmpty
      else { return true }
      pendingTextEvents.append(.insert(pasted))
    case .selectAll:
      if interaction.mode == .editing {
        pendingTextEvents.append(.selectAll)
      } else {
        interaction.selectAll(at: pointerPosition)
      }
    case .backspace:
      guard interaction.mode == .editing else { return true }
      pendingTextEvents.append(.backspace)
    case .deleteForward:
      guard interaction.mode == .editing else { return true }
      pendingTextEvents.append(.deleteForward)
    case .moveCaretLeft:
      guard interaction.mode == .editing else { return false }
      pendingTextEvents.append(.moveCaretLeft)
    case .moveCaretRight:
      guard interaction.mode == .editing else { return false }
      pendingTextEvents.append(.moveCaretRight)
    case .moveCaretUp, .moveCaretDown, .selectCaretUp, .selectCaretDown:
      guard interaction.mode == .editing else { return false }
      pendingTextEvents.append(editing)
    case .moveCaretToStart:
      guard interaction.mode == .editing else { return false }
      pendingTextEvents.append(.moveCaretToStart)
    case .moveCaretToEnd:
      guard interaction.mode == .editing else { return false }
      pendingTextEvents.append(.moveCaretToEnd)
    case .submit:
      if interaction.mode == .editing {
        pendingTextEvents.append(.submit)
      } else {
        pendingCommands.append(.action(.activate))
      }
    case .endEditing:
      guard interaction.mode == .editing else { return true }
      pendingTextEvents.append(.endEditing)
    }
    return true
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

#endif
