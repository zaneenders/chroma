@MainActor
public struct VariableHeightList: Block {
  let snapshotIdentity: ObjectIdentifier
  let count: Int
  let estimatedHeight: Float
  let overscan: Int
  let key: @MainActor (Int) -> StructuralKey
  let row: @MainActor (Int) -> any Block

  public init<ID: Hashable & Sendable>(
    snapshot: VirtualListSnapshot<ID>, estimatedHeight: Float, overscan: Int = 1,
    row: @escaping @MainActor (ID) -> any Block
  ) {
    precondition(estimatedHeight.isFinite && estimatedHeight >= 1 && overscan >= 0)
    precondition((Float(snapshot.count) * estimatedHeight).isFinite)
    snapshotIdentity = ObjectIdentifier(snapshot)
    count = snapshot.count
    self.estimatedHeight = estimatedHeight
    self.overscan = overscan
    key = { StructuralKey(snapshot.ids[$0]) }
    self.row = { row(snapshot.ids[$0]) }
  }

  public var body: Never { fatalError("VariableHeightList is lowered by NodeScene") }
}
