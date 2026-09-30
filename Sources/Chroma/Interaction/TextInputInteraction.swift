@MainActor
extension Interaction {
  func updateTextInput(
    id: WidgetID,
    rect: Rect,
    text: String,
    onChange: (String) -> Void,
    onSubmit: ((String) -> Void)? = nil,
    onEndEditing: (() -> CommandResult)? = nil,
    onTextEvent: ((TextEditEvent, String) -> String?)? = nil,
    pointerOffset: ((Point, Int?) -> Int)? = nil,
    verticalOffset: ((Int, Int) -> Int)? = nil,
    readOnly: Bool = false, submitInsertsNewline: Bool = false
  ) -> TextInputState {
    let selected = selectedLeafID == id
    let hovered = hoveredLeafID == id
    let held = pressedLeaf == id && input.pointerDown

    if selected && activatePending {
      activatePending = false
      let enterInMovement = enterTextPending || readOnly
      enterTextPending = false
      if editingLeaf != id {
        let clickedOffset: Int?
        if input.pointerReleased, let origin = dragOrigin, rect.contains(origin) {
          clickedOffset = pointerOffset?(origin, nil)
        } else {
          clickedOffset = nil
        }
        beginEditing(id, caretOffset: max(0, min(text.count, clickedOffset ?? (readOnly ? 0 : text.count))))
      }
      if enterInMovement {
        stopInput()
      } else {
        startInput()
      }
    }

    if selected, editingLeaf != id, isProcessingDrag, let origin = dragOrigin, rect.contains(origin) {
      let offset = pointerOffset?(origin, nil) ?? text.count
      beginEditing(id, caretOffset: max(0, min(text.count, offset)))
    }

    if editingLeaf == id {
      editingReadOnly = readOnly
      if readOnly { stopInput() }
    }
    let editing = editingLeaf == id
    if editing {
      editingText = text
      if input.textEvents.isEmpty && movementTextEvents.isEmpty && !isProcessingDrag {
        if inputLengthText != text {
          inputLengthText = text
          inputLength = text.count
        }
        caretOffset = max(0, min(caretOffset, inputLength))
        if let selection = textSelectionRange {
          let lower = max(0, min(selection.lowerBound, inputLength))
          let upper = max(lower, min(selection.upperBound, inputLength))
          textSelectionRange = lower == upper ? nil : lower..<upper
        }
        return TextInputState(
          hovered: hovered, focused: selected, held: held, editing: isTextEditing,
          caretOffset: caretOffset, selectionRange: textSelectionRange)
      }
      var characters = Array(text)
      caretOffset = max(0, min(caretOffset, characters.count))
      if let selection = textSelectionRange {
        let lowerBound = max(0, min(selection.lowerBound, characters.count))
        let upperBound = max(lowerBound, min(selection.upperBound, characters.count))
        textSelectionRange = lowerBound == upperBound ? nil : lowerBound..<upperBound
      }

      if isProcessingDrag, let origin = dragOrigin, rect.contains(origin) {
        let viewportCaret = caretOffset
        let offset: (Point) -> Int = { point in
          if let pointerOffset { return pointerOffset(point, viewportCaret) }
          let cellWidth = self.fontMetrics.cellAdvance
          guard cellWidth > 0, cellWidth.isFinite else { return 0 }
          return Int(((point.x - rect.minX) / cellWidth).rounded(.toNearestOrAwayFromZero))
        }
        if textDragAnchor == nil {
          textDragAnchor = max(0, min(characters.count, offset(origin)))
        }
        let anchor = textDragAnchor ?? caretOffset
        let current = max(0, min(characters.count, offset(dragCurrent)))
        caretOffset = current
        textSelectionRange = anchor == current ? nil : min(anchor, current)..<max(anchor, current)
      }

      var changed = false
      eventLoop: for incomingEvent in movementTextEvents + input.textEvents {
        let event: TextEditEvent = incomingEvent == .submit && submitInsertsNewline ? .insert("\n") : incomingEvent
        if readOnly || mode == .movement {
          switch event {
          case .insert, .delete, .backspace, .deleteForward, .cut, .paste, .submit: continue
          default: break
          }
        }
        if mode == .editing, let replacement = onTextEvent?(event, String(characters)) {
          characters = Array(replacement)
          caretOffset = characters.count
          textSelectionRange = nil
          changed = true
          continue
        }
        if let (unit, direction, extend) = event.movement {
          let anchor =
            textSelectionRange.map {
              caretOffset == $0.lowerBound ? $0.upperBound : $0.lowerBound
            } ?? caretOffset
          if !extend, let selection = textSelectionRange,
            unit != .document && unit != .vertical
          {
            caretOffset = direction == .backward ? selection.lowerBound : selection.upperBound
          } else {
            caretOffset = TextEditingOperation.boundary(
              in: characters, from: caretOffset, unit: unit, direction: direction,
              verticalOffset: verticalOffset)
          }
          textSelectionRange =
            extend && anchor != caretOffset
            ? min(anchor, caretOffset)..<max(anchor, caretOffset) : nil
          continue
        }
        if let (unit, direction) = event.deletion {
          let range =
            textSelectionRange
            ?? TextEditingOperation.deletionRange(
              in: characters, from: caretOffset, unit: unit, direction: direction)
          if !range.isEmpty {
            characters.replaceSubrange(range, with: [] as [Character])
            caretOffset = range.lowerBound
            changed = true
          }
          textSelectionRange = nil
          continue
        }
        switch event {
        case .copy, .cut, .paste:
          continue
        case .insert(let inserted):
          let range = textSelectionRange ?? caretOffset..<caretOffset
          let graft = Array(inserted)
          characters.replaceSubrange(range, with: graft)
          caretOffset = range.lowerBound + graft.count
          textSelectionRange = nil
          if !range.isEmpty || !graft.isEmpty { changed = true }
        case .selectAll:
          textSelectionRange = characters.isEmpty ? nil : 0..<characters.count
          caretOffset = characters.count
        case .submit:
          if let onSubmit {
            if changed {
              onChange(String(characters))
              changed = false
            }
            onSubmit(String(characters))
          } else {
            stopInput()
            break eventLoop
          }
        case .endEditing:
          if onEndEditing?() != .handled {
            stopInput()
            break eventLoop
          }
        default:
          break
        }
      }
      if changed {
        let updated = String(characters)
        editingText = updated
        onChange(updated)
      }
    }
    return TextInputState(
      hovered: hovered, focused: selected, held: held, editing: editing && isTextEditing,
      caretOffset: editing ? caretOffset : nil,
      selectionRange: editing ? textSelectionRange : nil)
  }

}

@MainActor
extension Interaction {
  func registerTextInput(
    id: WidgetID, rect: Rect, text: @escaping @MainActor () -> String,
    onChange: @escaping @MainActor (String) -> Void,
    onSubmit: (@MainActor (String) -> Void)? = nil,
    onEndEditing: (@MainActor () -> CommandResult)? = nil,
    onTextEvent: (@MainActor (TextEditEvent, String) -> String?)? = nil,
    pointerOffset: (@MainActor (Point, Int?) -> Int)? = nil,
    verticalOffset: (@MainActor (Int, Int) -> Int)? = nil,
    navigationIgnored: Bool = false, readOnly: Bool = false, submitInsertsNewline: Bool = false
  ) -> TextInputState {
    guard let parent = builderStack.last else {
      preconditionFailure("registerTextInput outside of a frame")
    }
    parent.children.append(
      FocusNode(
        kind: .leaf(id), rect: rect, hitRect: clippedRect(rect),
        canBeRevealed: parent.canBeRevealed, navigationIgnored: navigationIgnored))
    building.inputHandlers[id] = { [weak self] in
      guard let self else { return }
      _ = self.updateTextInput(
        id: id, rect: rect, text: text(), onChange: onChange, onSubmit: onSubmit,
        onEndEditing: onEndEditing, onTextEvent: onTextEvent,
        pointerOffset: pointerOffset, verticalOffset: verticalOffset, readOnly: readOnly,
        submitInsertsNewline: submitInsertsNewline)
    }
    let editing = editingLeaf == id
    if editing {
      let currentText = text()
      if inputLengthText != currentText {
        inputLengthText = currentText
        inputLength = currentText.count
      }
      editingText = currentText
      caretOffset = max(0, min(caretOffset, inputLength))
      if let selection = textSelectionRange {
        let lower = max(0, min(selection.lowerBound, inputLength))
        let upper = max(lower, min(selection.upperBound, inputLength))
        textSelectionRange = lower == upper ? nil : lower..<upper
      }
    }
    return TextInputState(
      hovered: hoveredLeafID == id, focused: selectedLeafID == id,
      held: pressedLeaf == id && input.pointerDown,
      editing: editing && isTextEditing, caretOffset: editing ? caretOffset : nil,
      selectionRange: editing ? textSelectionRange : nil)
  }
}

private enum TextEditingOperation {
  private enum Kind: Equatable { case space, word, punctuation }

  private static func kind(_ character: Character) -> Kind {
    if character.isWhitespace { return .space }
    if character.isLetter || character.isNumber || character == "_" { return .word }
    return .punctuation
  }

  static func boundary(
    in text: [Character], from offset: Int, unit: TextMovementUnit,
    direction: TextDirection, verticalOffset: ((Int, Int) -> Int)? = nil
  ) -> Int {
    let backward = direction == .backward
    switch unit {
    case .character: return max(0, min(text.count, offset + (backward ? -1 : 1)))
    case .document: return backward ? 0 : text.count
    case .vertical:
      return max(
        0,
        min(
          text.count,
          verticalOffset?(offset, backward ? -1 : 1) ?? (backward ? 0 : text.count)))
    case .word:
      var position = offset
      if backward {
        while position > 0 && kind(text[position - 1]) == .space { position -= 1 }
        if position > 0 {
          let group = kind(text[position - 1])
          while position > 0 && kind(text[position - 1]) == group { position -= 1 }
        }
      } else {
        if position < text.count && kind(text[position]) != .space {
          let group = kind(text[position])
          while position < text.count && kind(text[position]) == group { position += 1 }
        }
        while position < text.count && kind(text[position]) == .space { position += 1 }
      }
      return position
    }
  }

  static func deletionRange(
    in text: [Character], from offset: Int, unit: TextMovementUnit, direction: TextDirection
  ) -> Range<Int> {
    let target = boundary(in: text, from: offset, unit: unit, direction: direction)
    return min(offset, target)..<max(offset, target)
  }
}
