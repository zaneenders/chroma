#if METAL_BACKEND

import AppKit
import Chroma
import MetalKit

final class ChromaInputView: MTKView {
  var interaction: Interaction!
  private var pointerPosition = Point(x: -1, y: -1)
  private var pointerPressPosition = Point(x: -1, y: -1)
  private var pointerDown = false
  private var pressedEdge = false
  private var releasedEdge = false
  private var scroll = Point.zero
  private var pendingCommands: [UICommand] = []
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
    let command: UICommand?
    switch event.keyCode {
    case 48:
      command = event.modifierFlags.contains(.shift) ? .previousLeaf : .nextLeaf
    case 123: command = .left
    case 124: command = .right
    case 125: command = .down
    case 126: command = .up
    case 116: command = .pageUp
    case 121: command = .pageDown
    case 115: command = .home
    case 119: command = .end
    case 36, 76, 49: command = .activate
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
        command = nil
      }
    }
    if let command {
      pendingCommands.append(command)
    } else {
      super.keyDown(with: event)
    }
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
