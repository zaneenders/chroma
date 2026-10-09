import Dispatch
import Foundation
import Synchronization

/// Missing-glyph diagnostics, independent of fallback rendering.
///
/// The default reports at most 64 distinct scalar-prefix signatures and one suppression notice
/// per instance. Each signature contains at most 16 Unicode scalars, bounding retained metadata
/// and queued output even for arbitrarily long grapheme clusters. Reports sharing a truncated
/// prefix are deduplicated. No surrounding application text is retained or written.
///
/// Output runs on a private serial queue, never on the drawing thread or under the state lock.
/// A blocked sink can delay diagnostics, but cannot block painting. Pending diagnostics are
/// best effort and may be lost at process exit. The explicit `perOccurrence` mode is unbounded
/// and should only be used for short diagnostic sessions with a consuming sink.
public final class MissingGlyphWarnings: Sendable {
  public enum Policy: Sendable {
    case disabled
    case bounded
    case perOccurrence
  }

  /// Set CHROMA_MISSING_GLYPH_WARNINGS to `off` or `verbose` before creating the first atlas or accessing `shared`
  /// to override the bounded process-wide default. Unknown values use the bounded default.
  public static let shared = MissingGlyphWarnings(
    policy: policy(for: ProcessInfo.processInfo.environment["CHROMA_MISSING_GLYPH_WARNINGS"]))

  static let signatureLimit = 64
  static let scalarLimit = 16

  private struct State: Sendable {
    var signatures: Set<[UInt32]> = []
    var suppressed = false
  }

  private let state = Mutex(State())
  private let policy: Policy
  private let write: @Sendable (String) -> Void
  private let output = DispatchQueue(label: "chroma.font.missing-glyph")

  public init(
    policy: Policy = .bounded,
    write: @escaping @Sendable (String) -> Void = { line in
      try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
    }
  ) {
    self.policy = policy
    self.write = write
  }

  static func policy(for value: String?) -> Policy {
    switch value {
    case "off": .disabled
    case "verbose": .perOccurrence
    default: .bounded
    }
  }

  func report(_ character: Character) {
    switch policy {
    case .disabled:
      return
    case .perOccurrence:
      enqueue(Self.message(character.unicodeScalars.map(\.value), truncated: false))
    case .bounded:
      // Stop before reading/hashing scalars once the lifetime budget is exhausted.
      guard !state.withLock({ $0.suppressed }) else { return }
      var signature = character.unicodeScalars.prefix(Self.scalarLimit + 1).map(\.value)
      let truncated = signature.count > Self.scalarLimit
      if truncated { signature[Self.scalarLimit] = 0x11_0000 }
      let result = state.withLock { state -> Int in
        guard !state.suppressed, !state.signatures.contains(signature) else { return 0 }
        guard state.signatures.count < Self.signatureLimit else {
          state.suppressed = true
          return 2
        }
        state.signatures.insert(signature)
        return 1
      }
      if result == 1 {
        enqueue(Self.message(Array(signature.prefix(Self.scalarLimit)), truncated: truncated))
      } else if result == 2 {
        enqueue("[warning] chroma.font.missing-glyph further-diagnostics-suppressed limit=64\n")
      }
    }
  }

  private static func message(_ scalars: [UInt32], truncated: Bool) -> String {
    let codepoints = scalars.map {
      let hex = String($0, radix: 16, uppercase: true)
      return "U+" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
    }.joined(separator: ",")
    return "[warning] chroma.font.missing-glyph codepoints=\(codepoints)\(truncated ? " truncated=true" : "")\n"
  }

  private func enqueue(_ line: String) {
    let write = self.write
    output.async { write(line) }
  }

  // For deterministic tests only; painting never waits for the diagnostic sink.
  func waitForPendingReports() { output.sync {} }
}
