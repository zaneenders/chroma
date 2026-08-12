public struct Glyph: Sendable {
  public var rows: [UInt32]

  public init(rows: [UInt32] = Array(repeating: 0, count: 28)) {
    precondition(rows.count == 28, "A 20×28 glyph must contain exactly 28 rows")
    precondition(rows.allSatisfy { $0 < (1 << 20) }, "Glyph rows may contain at most 20 bits")
    self.rows = rows
  }
}
