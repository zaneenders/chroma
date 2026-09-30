package struct WidgetID: Hashable, Sendable {
  package let rawValue: UInt64
  let structuralPath: StructuralPath?

  init(path: StructuralPath) {
    rawValue = 0
    structuralPath = path
  }

  package init(rawValue: UInt64) {
    structuralPath = nil
    self.rawValue = rawValue
  }

  package init(_ string: String) {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
      hash ^= UInt64(byte)
      hash &*= 0x0000_0100_0000_01b3
    }
    self.init(rawValue: hash)
  }
}
