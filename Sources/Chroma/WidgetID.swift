public struct WidgetID: Hashable, Sendable {
  public let rawValue: UInt64
  private var structuralPath: StructuralPath?

  init(path: StructuralPath) {
    rawValue = 0
    structuralPath = path
  }

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  public init(_ string: String) {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
      hash ^= UInt64(byte)
      hash &*= 0x0000_0100_0000_01b3
    }
    self.init(rawValue: hash)
  }
}
