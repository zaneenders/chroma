@MainActor
extension Interaction {
  package var selectionDescription: String {
    guard let selection else { return "—" }
    let path = selection.isEmpty ? "·" : selection.map(String.init).joined(separator: ".")
    let kind = selectedLeafID != nil ? "leaf" : selection.isEmpty ? "root" : "group"
    return "\(path) (\(kind))"
  }

  package var lastMacroDescription: String {
    lastMacro.isEmpty ? "—" : lastMacro.map(\.label).joined(separator: " ")
  }

}
