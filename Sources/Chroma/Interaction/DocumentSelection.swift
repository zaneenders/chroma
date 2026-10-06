@MainActor
extension Interaction {
  struct ReadOnlyText {
    let text: String
    let reference: TextRunReference
    let rect: Rect
    let hitRect: Rect
    let pointerOffset: (@MainActor (Point, Int?) -> Int)?
    let verticalOffset: (@MainActor (Int, Int) -> Int)?
  }

  private enum ImplicitDocumentID: Sendable { case window }
  static let implicitDocument = TextID(ImplicitDocumentID.window)

  func textLeafIDs(in node: FocusNode?) -> [WidgetID] {
    guard let node else { return [] }
    var ids: [WidgetID] = []
    node.walk(into: &ids) { node, ids in
      if let id = node.leafID, registrations.readOnlyTexts[id] != nil { ids.append(id) }
    }
    return ids
  }

  func installDocuments(in tree: FocusNode) {
    var runs: [TextDocument.Run] = []
    tree.walk(into: &runs) { node, runs in
      guard let id = node.leafID, let text = building.readOnlyTexts[id],
        text.reference.document == Self.implicitDocument
      else { return }
      runs.append(.init(id: text.reference.run, text: text.text, separator: "\n"))
    }
    for text in building.readOnlyTexts.values where text.reference.document != Self.implicitDocument {
      guard let document = building.documents[text.reference.document],
        let index = document.index(of: .init(run: text.reference.run, offset: text.reference.offset))
      else { preconditionFailure("Text run must belong to the complete document") }
      let characters = Array(document.runs[index].text)
      let end = text.reference.offset + text.text.count
      precondition(end <= characters.count, "Text fragment exceeds its document run")
      precondition(
        String(characters[text.reference.offset..<end]) == text.text, "Text fragment differs from its document run")
    }
    if !runs.isEmpty {
      building.documents[Self.implicitDocument] = TextDocument(id: Self.implicitDocument, runs: runs)
    }
    let hadSelection = textSelection.selection != nil
    textSelection.install(building.documents)
    if hadSelection, textSelection.selection == nil, editingReadOnly { textSelectionRange = nil }
  }

  func documentRange(for id: WidgetID) -> Range<Int>? {
    guard let selection = textSelection.selection,
      let text = (builderRoot == nil ? registrations : building).readOnlyTexts[id],
      selection.document == text.reference.document,
      let range = textSelection.documents[selection.document]?.range(in: text.reference.run, selection: selection)
    else { return nil }
    let lower = max(0, min(text.text.count, range.lowerBound - text.reference.offset))
    let upper = max(lower, min(text.text.count, range.upperBound - text.reference.offset))
    return lower..<upper
  }

  func documentCopyText() -> String? { textSelection.selectedText() }

  func selectTextScope() -> Bool {
    if let selection = textSelection.selection, selection.document != Self.implicitDocument {
      textSelection.selectAll()
      synchronizeDocumentCaret()
      requestRedraw()
      return true
    }
    let path = navigation?.node(at: navigationPath)?.renderPath ?? []
    let ids = textLeafIDs(in: tree?.node(at: path))
    guard let first = ids.first.flatMap({ registrations.readOnlyTexts[$0] }),
      let last = ids.last.flatMap({ registrations.readOnlyTexts[$0] }),
      first.reference.document == last.reference.document,
      let document = textSelection.documents[first.reference.document]
    else { return false }
    let implicit = document.id == Self.implicitDocument
    guard let firstRun = implicit ? document.runs.first(where: { $0.id == first.reference.run }) : document.runs.first,
      let lastRun = implicit ? document.runs.first(where: { $0.id == last.reference.run }) : document.runs.last
    else { return false }
    textSelection.select(
      .init(
        document: document.id, anchor: .init(run: firstRun.id, offset: 0),
        active: .init(run: lastRun.id, offset: lastRun.text.count)))
    synchronizeDocumentCaret()
    requestRedraw()
    return true
  }

  func beginDocumentSelection(id: WidgetID, offset: Int) {
    guard let text = registrations.readOnlyTexts[id] else { return }
    let position = TextDocument.Position(run: text.reference.run, offset: text.reference.offset + offset)
    textSelection.select(.init(document: text.reference.document, anchor: position, active: position))
  }

  func synchronizeDocumentCaret() {
    guard let selection = textSelection.selection else { return }
    guard
      let id = textLeafIDs(in: tree).last(where: { id in
        guard let text = registrations.readOnlyTexts[id] else { return false }
        return text.reference.document == selection.document && text.reference.run == selection.active.run
          && (text.reference.offset...(text.reference.offset + text.text.count)).contains(selection.active.offset)
      }), let text = registrations.readOnlyTexts[id]
    else {
      if editingReadOnly { endEditing(preservingDocumentSelection: true) }
      return
    }
    editingLeaf = id
    editingReadOnly = true
    mode = .movement
    editingText = text.text
    caretOffset = selection.active.offset - text.reference.offset
    textSelectionRange = documentRange(for: id).flatMap { $0.isEmpty ? nil : $0 }
  }

  func processDocumentInput() {
    if isProcessingDrag {
      if textSelection.selection == nil || input.pointerPressed, let origin = dragOrigin,
        let path = tree?.hitTest(origin), let id = tree?.node(at: path)?.leafID,
        let text = registrations.readOnlyTexts[id]
      {
        let offset = text.pointerOffset?(origin, nil) ?? 0
        beginDocumentSelection(id: id, offset: max(0, min(text.text.count, offset)))
        textSelection.setSelecting(true)
      }
      if var selection = textSelection.selection, textSelection.isSelecting {
        let candidates = textLeafIDs(in: tree).compactMap { registrations.readOnlyTexts[$0] }.filter {
          $0.reference.document == selection.document && $0.hitRect != .zero
        }
        let text =
          candidates.first(where: { $0.hitRect.contains(dragCurrent) })
          ?? candidates.min { distance(dragCurrent, to: $0.rect) < distance(dragCurrent, to: $1.rect) }
        if let text {
          let offset = text.pointerOffset?(dragCurrent, nil) ?? (dragCurrent.y < text.rect.minY ? 0 : text.text.count)
          selection.active = .init(
            run: text.reference.run, offset: text.reference.offset + max(0, min(text.text.count, offset)))
          textSelection.select(selection)
        }
      }
    }
    if input.pointerReleased { textSelection.setSelecting(false) }
    if textSelection.selection == nil, editingReadOnly, let id = editingLeaf {
      beginDocumentSelection(id: id, offset: caretOffset)
    }
    for event in movementTextEvents + input.textEvents {
      guard var selection = textSelection.selection, let document = textSelection.documents[selection.document],
        let index = document.index(of: selection.active)
      else { continue }
      if event == .selectAll {
        textSelection.selectAll()
        continue
      }
      guard let (unit, direction, extend) = event.movement else { continue }
      let backward = direction == .backward
      if !extend, selection.anchor != selection.active, unit != .document && unit != .vertical,
        let bounds = document.bounds(of: selection)
      {
        selection.active = backward ? bounds.lower : bounds.upper
      } else if unit == .document {
        let run = backward ? document.runs[0] : document.runs[document.runs.count - 1]
        selection.active = .init(run: run.id, offset: backward ? 0 : run.text.count)
      } else {
        let run = document.runs[index]
        let visible = textLeafIDs(in: tree).compactMap { registrations.readOnlyTexts[$0] }.last {
          $0.reference.document == document.id && $0.reference.run == run.id
            && ($0.reference.offset...($0.reference.offset + $0.text.count)).contains(selection.active.offset)
        }
        let next = TextEditingOperation.boundary(
          in: Array(run.text), from: selection.active.offset, unit: unit, direction: direction,
          verticalOffset: { offset, direction in
            guard let visible, let vertical = visible.verticalOffset else {
              return TextLayout(run.text).verticalOffset(offset, direction: direction)
            }
            return visible.reference.offset + vertical(offset - visible.reference.offset, direction)
          })
        let destination = index + (backward ? -1 : 1)
        if next == selection.active.offset, document.runs.indices.contains(destination) {
          let run = document.runs[destination]
          selection.active = .init(run: run.id, offset: backward ? run.text.count : 0)
        } else {
          selection.active = .init(run: run.id, offset: next)
        }
      }
      if !extend { selection = .init(document: document.id, anchor: selection.active, active: selection.active) }
      textSelection.select(selection)
    }
    synchronizeDocumentCaret()
    if !(movementTextEvents + input.textEvents).isEmpty, let id = editingLeaf,
      let path = tree?.findLeaf(id), let tree
    {
      reveal(path, in: tree)
    }
  }

  private func distance(_ point: Point, to rect: Rect) -> Float {
    let x = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let y = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return x * x + y * y
  }
}
