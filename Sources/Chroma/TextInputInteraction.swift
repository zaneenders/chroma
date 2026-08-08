@MainActor
extension Interaction {
  func textInputBehavior(
    id: WidgetID,
    rect: Rect,
    text: String,
    onChange: (String) -> Void,
    onSubmit: ((String) -> Void)? = nil
  ) -> TextInputState {
    guard let parent = builderStack.last else {
      preconditionFailure("textInputBehavior outside of a frame; call beginFrame first")
    }
    parent.children.append(FocusNode(kind: .leaf(id), rect: clippedRect(rect)))

    let selected = selectedLeafID == id
    let held = pressedLeaf == id && input.pointerDown

    if selected && activatePending {
      activatePending = false
      beginEditing(id, caretOffset: text.count)
    }

    var editing = editingLeaf == id
    if editing {
      editingText = text
      var characters = Array(text)
      caretOffset = min(caretOffset, characters.count)
      var changed = false
      eventLoop: for event in input.textEvents {
        switch event {
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
          endEditing()
          editing = false
          break eventLoop
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
      caretOffset: editing ? caretOffset : nil)
  }

}
