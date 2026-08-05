@MainActor
extension Interaction {
  public func textInputBehavior(
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
      editingLeaf = id
      caretOffset = text.count
    }

    var editing = editingLeaf == id
    if editing {
      var characters = Array(text)
      caretOffset = min(caretOffset, characters.count)
      var changed = false
      eventLoop: for event in input.textEvents {
        switch event {
        case .insert(let inserted):
          let graft = Array(inserted)
          characters.insert(contentsOf: graft, at: caretOffset)
          caretOffset += graft.count
          changed = true
        case .backspace:
          if caretOffset > 0 {
            characters.remove(at: caretOffset - 1)
            caretOffset -= 1
            changed = true
          }
        case .deleteForward:
          if caretOffset < characters.count {
            characters.remove(at: caretOffset)
            changed = true
          }
        case .moveCaretLeft:
          caretOffset = max(0, caretOffset - 1)
        case .moveCaretRight:
          caretOffset = min(characters.count, caretOffset + 1)
        case .moveCaretToStart:
          caretOffset = 0
        case .moveCaretToEnd:
          caretOffset = characters.count
        case .submit:
          if let onSubmit {
            if changed {
              onChange(String(characters))
              changed = false
            }
            onSubmit(String(characters))
          } else {
            editingLeaf = nil
            editing = false
            break eventLoop
          }
        case .endEditing:
          editingLeaf = nil
          editing = false
          break eventLoop
        }
      }
      if changed {
        onChange(String(characters))
      }
    }
    return TextInputState(
      hovered: selected, held: held, editing: editing,
      caretOffset: editing ? caretOffset : nil)
  }

}
