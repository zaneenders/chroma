@MainActor
public struct VariableHeightList: Block {
  let snapshotIdentity: ObjectIdentifier
  let selection: VirtualListSelection?
  let controller: ScrollViewController?
  let sticksToBottom: Bool
  let index: @MainActor (StructuralKey) -> Int?
  let count: Int
  let estimatedHeight: Float
  let overscan: Int
  let key: @MainActor (Int) -> StructuralKey
  let row: @MainActor (Int) -> any Block

  public init<ID: Hashable & Sendable>(
    snapshot: VirtualListSnapshot<ID>, estimatedHeight: Float, overscan: Int = 1,
    controller: ScrollViewController? = nil, sticksToBottom: Bool = false,
    selection: ScrollSelection<ID>? = nil,
    row: @escaping @MainActor (ID) -> any Block
  ) {
    precondition(estimatedHeight.isFinite && estimatedHeight >= 1 && overscan >= 0)
    precondition((Float(snapshot.count) * estimatedHeight).isFinite)
    self.selection = selection.map { VirtualListSelection(snapshot: snapshot, selection: $0) }
    self.controller = controller
    self.sticksToBottom = sticksToBottom
    index = { key in (key.value as? ID).flatMap { snapshot.index(of: $0) } }
    snapshotIdentity = ObjectIdentifier(snapshot)
    count = snapshot.count
    self.estimatedHeight = estimatedHeight
    self.overscan = overscan
    key = { StructuralKey(snapshot.ids[$0]) }
    self.row = { row(snapshot.ids[$0]) }
  }

  init(
    identity: ObjectIdentifier, count: Int, estimatedHeight: Float,
    controller: ScrollViewController, sticksToBottom: Bool,
    selection: VirtualListSelection?, key: @escaping @MainActor (Int) -> StructuralKey,
    index: @escaping @MainActor (StructuralKey) -> Int?, row: @escaping @MainActor (Int) -> any Block
  ) {
    snapshotIdentity = identity
    self.count = count
    self.estimatedHeight = estimatedHeight
    overscan = 1
    self.controller = controller
    self.sticksToBottom = sticksToBottom
    self.selection = selection
    self.key = key
    self.index = index
    self.row = row
  }

  public var body: Never { fatalError("VariableHeightList is lowered by NodeScene") }
}

@MainActor
struct VirtualListSelection {
  let selectedKey: @MainActor () -> StructuralKey?
  let select: @MainActor (StructuralKey) -> Void
  let move: @MainActor (Int) -> StructuralKey?

  init(
    selectedKey: @escaping @MainActor () -> StructuralKey?,
    select: @escaping @MainActor (StructuralKey) -> Void,
    move: @escaping @MainActor (Int) -> StructuralKey?
  ) {
    self.selectedKey = selectedKey
    self.select = select
    self.move = move
  }

  init<ID: Hashable & Sendable>(snapshot: VirtualListSnapshot<ID>, selection: ScrollSelection<ID>) {
    selectedKey = {
      guard let id = selection.selectedID else { return nil }
      if snapshot.index(of: id) != nil { return StructuralKey(id) }
      return snapshot.ids.first.map(StructuralKey.init)
    }
    select = { selection.selectedID = $0.value as? ID }
    move = { distance in
      guard snapshot.count > 0 else { selection.selectedID = nil; return nil }
      let index = selection.selectedID.flatMap { snapshot.index(of: $0) } ?? 0
      let next = max(0, min(snapshot.count - 1, index + distance))
      selection.selectedID = snapshot.ids[next]
      return StructuralKey(snapshot.ids[next])
    }
  }
}
