@MainActor
extension Interaction {
  func textInputBehavior(
    id: WidgetID,
    rect: Rect,
    text: String,
    onChange: (String) -> Void,
    onSubmit: ((String) -> Void)? = nil,
    onEndEditing: (() -> CommandResult)? = nil,
    pointerOffset: ((Point, Int?) -> Int)? = nil,
    verticalOffset: ((Int, Int) -> Int)? = nil
  ) -> TextInputState {
    guard let parent = builderStack.last else {
      preconditionFailure("textInputBehavior outside of a frame; call beginFrame first")
    }
    parent.children.append(FocusNode(kind: .leaf(id), rect: clippedRect(rect)))

    let selected = selectedLeafID == id
    let held = pressedLeaf == id && input.pointerDown

    if selected && activatePending {
      activatePending = false
      if editingLeaf != id {
        let clickedOffset: Int?
        if input.pointerReleased, let origin = dragOrigin, rect.contains(origin) {
          clickedOffset = pointerOffset?(origin, nil)
        } else {
          clickedOffset = nil
        }
        beginEditing(id, caretOffset: max(0, min(text.count, clickedOffset ?? text.count)))
      }
    }

    if selected, editingLeaf != id, isProcessingDrag, let origin = dragOrigin, rect.contains(origin) {
      let offset = pointerOffset?(origin, nil) ?? text.count
      beginEditing(id, caretOffset: max(0, min(text.count, offset)))
    }

    var editing = editingLeaf == id
    if editing {
      editingText = text
      var characters = Array(text)
      caretOffset = max(0, min(caretOffset, characters.count))
      if let selection = textSelectionRange {
        let lowerBound = max(0, min(selection.lowerBound, characters.count))
        let upperBound = max(lowerBound, min(selection.upperBound, characters.count))
        textSelectionRange = lowerBound == upperBound ? nil : lowerBound..<upperBound
      }

      if isProcessingDrag, let origin = dragOrigin, rect.contains(origin) {
        // Keep the origin's hit-test stable if moving the caret scrolls the viewport
        // on a later drag frame.
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
      eventLoop: for event in input.textEvents {
        switch event {
        case .copy, .cut, .paste:
          // TODO: is continue the best way to handle this?
          // Backends own the pasteboard and intercept these before delivery.
          continue
        case .insert(let inserted):
          if let range = textSelectionRange {
            characters.removeSubrange(range)
            caretOffset = range.lowerBound
            textSelectionRange = nil
          }
          let graft = Array(inserted)
          characters.insert(contentsOf: graft, at: caretOffset)
          caretOffset += graft.count
          changed = true
        case .backspace:
          if let range = textSelectionRange {
            characters.removeSubrange(range)
            caretOffset = range.lowerBound
            textSelectionRange = nil
            changed = true
          } else if caretOffset > 0 {
            characters.remove(at: caretOffset - 1)
            caretOffset -= 1
            changed = true
          }
        case .deleteForward:
          if let range = textSelectionRange {
            characters.removeSubrange(range)
            caretOffset = range.lowerBound
            textSelectionRange = nil
            changed = true
          } else if caretOffset < characters.count {
            characters.remove(at: caretOffset)
            changed = true
          }
        case .moveCaretLeft:
          caretOffset = textSelectionRange?.lowerBound ?? max(0, caretOffset - 1)
          textSelectionRange = nil
        case .moveCaretRight:
          caretOffset = textSelectionRange?.upperBound ?? min(characters.count, caretOffset + 1)
          textSelectionRange = nil
        case .moveCaretUp:
          let offset = verticalOffset?(caretOffset, -1) ?? 0
          caretOffset = max(0, min(characters.count, offset))
          textSelectionRange = nil
        case .moveCaretDown:
          let offset = verticalOffset?(caretOffset, 1) ?? characters.count
          caretOffset = max(0, min(characters.count, offset))
          textSelectionRange = nil
        case .selectCaretUp, .selectCaretDown:
          let direction = event == .selectCaretUp ? -1 : 1
          let anchor: Int
          if let selection = textSelectionRange {
            anchor = caretOffset == selection.lowerBound ? selection.upperBound : selection.lowerBound
          } else {
            anchor = caretOffset
          }
          let offset =
            verticalOffset?(caretOffset, direction)
            ?? (direction < 0 ? 0 : characters.count)
          caretOffset = max(0, min(characters.count, offset))
          textSelectionRange =
            anchor == caretOffset
            ? nil
            : min(anchor, caretOffset)..<max(anchor, caretOffset)
        case .moveCaretToStart:
          caretOffset = 0
          textSelectionRange = nil
        case .moveCaretToEnd:
          caretOffset = characters.count
          textSelectionRange = nil
        case .selectAll:
          textSelectionRange = 0..<characters.count
          caretOffset = characters.count
        case .submit:
          if let onSubmit {
            if changed {
              onChange(String(characters))
              changed = false
            }
            onSubmit(String(characters))
          } else {
            endEditing()
            editing = false
            break eventLoop
          }
        case .endEditing:
          if onEndEditing?() != .handled {
            endEditing()
            editing = false
            break eventLoop
          }
        }
      }
      if changed {
        let updated = String(characters)
        editingText = updated
        onChange(updated)
      }
    }
    return TextInputState(
      hovered: selected, held: held, editing: editing,
      caretOffset: editing ? caretOffset : nil,
      selectionRange: editing ? textSelectionRange : nil)
  }

}
