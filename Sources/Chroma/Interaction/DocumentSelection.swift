@MainActor
extension Interaction {
  struct TextEndpoint {
    var id: WidgetID
    var offset: Int
  }

  func textLeafIDs(in node: InteractionNode?) -> [WidgetID] {
    guard let node else { return [] }
    if let id = node.leafID { return registrations.readOnlyTexts[id] == nil ? [] : [id] }
    return node.children.flatMap { textLeafIDs(in: $0) }
  }

  func documentRange(for id: WidgetID) -> Range<Int>? {
    guard let anchor = documentAnchor, let end = documentEnd else { return nil }
    let ids = textLeafIDs(in: tree)
    guard let a = ids.firstIndex(of: anchor.id), let b = ids.firstIndex(of: end.id),
      let index = ids.firstIndex(of: id), let text = registrations.readOnlyTexts[id]?()
    else { return nil }
    let forward = a < b || (a == b && anchor.offset <= end.offset)
    let start = forward ? anchor : end
    let finish = forward ? end : anchor
    guard index >= min(a, b), index <= max(a, b) else { return nil }
    let lower = id == start.id ? min(text.count, start.offset) : 0
    let upper = id == finish.id ? min(text.count, finish.offset) : text.count
    return max(0, lower)..<max(lower, upper)
  }

  func documentCopyText() -> String? {
    guard documentAnchor != nil else { return nil }
    let values = textLeafIDs(in: tree).compactMap { id -> String? in
      guard let range = documentRange(for: id), !range.isEmpty,
        let text = registrations.readOnlyTexts[id]?()
      else { return nil }
      return String(Array(text)[range])
    }
    return values.isEmpty ? nil : values.joined(separator: "\n")
  }

  func selectTextScope() -> Bool {
    let path = navigation?.node(at: navigationPath)?.renderPath ?? []
    let ids = textLeafIDs(in: tree?.node(at: path))
    guard let first = ids.first, let last = ids.last else { return false }
    documentAnchor = TextEndpoint(id: first, offset: 0)
    documentEnd = TextEndpoint(id: last, offset: registrations.readOnlyTexts[last]?().count ?? 0)
    requestRedraw()
    return true
  }

  func extendDocumentSelection(from id: WidgetID, anchor: Int, next: Int, direction: Int) -> Bool {
    guard let text = registrations.readOnlyTexts[id]?() else { return false }
    if documentAnchor == nil { documentAnchor = TextEndpoint(id: id, offset: anchor) }
    let ids = textLeafIDs(in: tree)
    if next == caretOffset, let index = ids.firstIndex(of: id), ids.indices.contains(index + direction) {
      let destination = ids[index + direction]
      let offset = direction > 0 ? 0 : (registrations.readOnlyTexts[destination]?().count ?? 0)
      focus(destination)
      beginEditing(destination, caretOffset: offset)
      editingReadOnly = true
      documentEnd = TextEndpoint(id: destination, offset: offset)
    } else {
      documentEnd = TextEndpoint(id: id, offset: min(text.count, next))
    }
    return true
  }
}
