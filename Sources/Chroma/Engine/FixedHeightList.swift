@MainActor
public struct FixedHeightList: Block {
  let count: Int
  let rowHeight: Float
  let overscan: Int
  let key: @MainActor (Int) -> StructuralKey
  let row: @MainActor (Int) -> any Block

  public init(
    count: Int, rowHeight: Float, overscan: Int = 1,
    row: @escaping @MainActor (Int) -> any Block
  ) {
    self.init(count: count, rowHeight: rowHeight, overscan: overscan, key: { StructuralKey($0) }, row: row)
  }

  public init<ID: Hashable & Sendable>(
    snapshot: VirtualListSnapshot<ID>, rowHeight: Float, overscan: Int = 1,
    row: @escaping @MainActor (ID) -> any Block
  ) {
    self.init(
      count: snapshot.count, rowHeight: rowHeight, overscan: overscan,
      key: { StructuralKey(snapshot.ids[$0]) },
      row: { row(snapshot.ids[$0]) })
  }

  init(
    count: Int, rowHeight: Float, overscan: Int = 1,
    key: @escaping @MainActor (Int) -> StructuralKey,
    row: @escaping @MainActor (Int) -> any Block
  ) {
    precondition(count >= 0 && rowHeight.isFinite && rowHeight > 0 && overscan >= 0)
    precondition((Float(count) * rowHeight).isFinite)
    self.count = count
    self.rowHeight = rowHeight
    self.overscan = overscan
    self.key = key
    self.row = row
  }

  public var body: Never { fatalError("FixedHeightList is lowered by NodeScene") }

  func visibleRange(offset: Float, height: Float) -> Range<Int> {
    guard count > 0, height > 0 else { return 0..<0 }
    let first = Int(min(Double(count), max(0, Double(offset / rowHeight).rounded(.down))))
    let end = Int(min(Double(count), max(0, Double((offset + height) / rowHeight).rounded(.up))))
    return max(0, first - min(first, overscan))..<min(count, end + min(count - end, overscan))
  }
}
