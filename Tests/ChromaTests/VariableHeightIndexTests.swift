import Testing

@testable import Chroma

struct VariableHeightIndexTests {
  @Test func estimatesJumpDirectlyIntoLargeCollections() {
    for count in [1_000, 100_000, 1_000_000] {
      let index = VariableHeightIndex(count: count, estimatedHeight: 20)
      #expect(index.measuredCount == 0)
      #expect(index.totalHeight == Double(count) * 20)
      #expect(index.visibleRange(offset: Double(count - 3) * 20, height: 40, overscan: 0) == (count - 3)..<(count - 1))
      #expect(index.visibleRange(offset: 0, height: 40) == 0..<3)
    }
  }

  @Test func measurementsReplaceEstimatesAndCanBeReplaced() {
    var index = VariableHeightIndex(count: 5, estimatedHeight: 20)
    index.measure(0, height: 40)
    index.measure(2, height: 10)
    #expect(index.totalHeight == 110)
    #expect(index.position(of: 3) == 70)
    #expect(index.height(at: 1) == 20)
    #expect(index.height(at: 2) == 10)
    #expect(index.row(at: 39) == 0)
    #expect(index.row(at: 40) == 1)
    #expect(index.row(at: 69) == 2)
    #expect(index.row(at: 70) == 3)
    index.measure(0, height: 20)
    #expect(index.totalHeight == 90)
    #expect(index.measuredCount == 2)
    #expect(index.position(of: 3) == 50)
  }

  @Test func measuredRangesMatchLinearReference() {
    let heights = (0..<257).map { Double(($0 * 17) % 53 + 1) }
    var index = VariableHeightIndex(count: heights.count, estimatedHeight: 20)
    for row in heights.indices.reversed() { index.measure(row, height: heights[row]) }
    var position: Double = 0
    for row in heights.indices {
      #expect(index.position(of: row) == position)
      #expect(index.row(at: position) == row)
      #expect(index.row(at: position + heights[row] - 0.5) == row)
      #expect(index.visibleRange(offset: position, height: heights[row], overscan: 0) == row..<(row + 1))
      position += heights[row]
    }
    #expect(index.totalHeight == position)
  }

  @Test func emptyAndOutOfBoundsViewportsStayBounded() {
    let empty = VariableHeightIndex(count: 0, estimatedHeight: 20)
    #expect(empty.totalHeight == 0)
    #expect(empty.row(at: 10) == 0)
    #expect(empty.visibleRange(offset: 0, height: 40).isEmpty)
    let index = VariableHeightIndex(count: 5, estimatedHeight: 20)
    #expect(index.row(at: -10) == 0)
    #expect(index.row(at: 1000) == 4)
    #expect(index.visibleRange(offset: 80, height: 40) == 3..<5)
    #expect(index.visibleRange(offset: 0, height: 0).isEmpty)
  }

  @Test func valueCopiesKeepMeasurementsIndependent() {
    var original = VariableHeightIndex(count: 1_000_000, estimatedHeight: 20)
    original.measure(500_000, height: 100)
    var copy = original
    copy.measure(500_000, height: 40)
    #expect(original.totalHeight == 20_000_080)
    #expect(copy.totalHeight == 20_000_020)
    #expect(copy.row(at: 10_000_039) == 500_000)
    #expect(copy.row(at: 10_000_040) == 500_001)
  }
}
