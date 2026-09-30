import Foundation

final class MissingGlyphWarnings: Sendable {
  static let shared = MissingGlyphWarnings()

  private let write: @Sendable (String) -> Void

  init(
    write: @escaping @Sendable (String) -> Void = { line in
      try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
    }
  ) {
    self.write = write
  }

  func report(_ character: Character) {
    let codepoints = character.unicodeScalars.map {
      let hex = String($0.value, radix: 16, uppercase: true)
      return "U+" + String(repeating: "0", count: max(0, 4 - hex.count)) + hex
    }.joined(separator: ",")
    write("[warning] chroma.font.missing-glyph codepoints=\(codepoints)\n")
  }
}
