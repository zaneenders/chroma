@MainActor
struct FixedHeightList: Block {
  let count: Int
  let rowHeight: Float
  let overscan: Int
  let key: @MainActor (Int) -> StructuralKey
  let row: @MainActor (Int) -> any Block

  init(
    count: Int, rowHeight: Float, overscan: Int = 1,
    key: @escaping @MainActor (Int) -> StructuralKey = { StructuralKey($0) },
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

  var body: Never { fatalError("FixedHeightList is lowered by NodeScene") }

  func visibleRange(offset: Float, height: Float) -> Range<Int> {
    guard count > 0, height > 0 else { return 0..<0 }
    let first = Int(min(Double(count), max(0, Double(offset / rowHeight).rounded(.down))))
    let end = Int(min(Double(count), max(0, Double((offset + height) / rowHeight).rounded(.up))))
    return max(0, first - min(first, overscan))..<min(count, end + min(count - end, overscan))
  }
}
