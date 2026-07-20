/// A stable identity for an interactive widget across frames.
///
/// Blocks are re-evaluated value types, so interaction state (`hot`,
/// `active`) is keyed by explicit IDs rather than object identity. Derive an
/// ID from a label or a scoped string such as `"check:wireframe"` — two
/// widgets sharing an ID fight over the pointer, so keep them unique.
public struct WidgetID: Hashable, Sendable {
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  /// Hashes a string into an ID (FNV-1a, stable across launches).
  public init(_ string: String) {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
      hash ^= UInt64(byte)
      hash &*= 0x0000_0100_0000_01b3
    }
    self.init(rawValue: hash)
  }
}
