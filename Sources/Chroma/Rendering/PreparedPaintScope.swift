/// An update owns opaque custom-wrapper children until its corresponding paint finishes.
/// No values survive the operation. Clearing is explicit to break context/child closure cycles.
@MainActor
final class PreparedPaintScope {
  private struct Entry {
    let path: StructuralPath
    let node: BlockEngine.Resolved
  }
  private var entries: [Entry] = []
  private var next = 0

  func remember(context: BlockContext, node: BlockEngine.Resolved) {
    entries.append(Entry(path: context.structuralPath, node: node))
  }

  func take(context: BlockContext) -> BlockEngine.Resolved {
    precondition(next < entries.count, "Painting requires a preceding matching registration in this update")
    let entry = entries[next]
    precondition(
      entry.path == context.structuralPath,
      "Custom registration and painting must visit children in the same order")
    next += 1
    return entry.node
  }

  func reset() {
    entries.removeAll()
    next = 0
  }
}

extension BlockContext {
  /// Registers an ordered event observer. It runs once after core input dispatch,
  /// before release/drag cleanup; presentation never invokes it.
  public func registerInputHandler(_ handler: @escaping @MainActor (InputState) -> Void) {
    interaction.building.inputObservers.append(handler)
  }
}
