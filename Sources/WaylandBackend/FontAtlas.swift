#if WAYLAND_BACKEND

import Chroma
import ChromaFont

/// Builds the printable-ASCII portion of Chroma's 20×28 bitmap font as an
/// RGBA texture for OpenGL ES. The full glyph map remains owned by ChromaFont;
/// this backend uses `?` for glyphs outside the initial ASCII atlas.
struct FontAtlas {
  static let firstScalar: UInt32 = 32
  static let lastScalar: UInt32 = 126

  let width: Int
  let height: Int
  let glyphWidth: Int
  let glyphHeight: Int
  let cellWidth: Int
  let pixels: [UInt8]

  init(metrics: FontMetrics = FontMetrics()) {
    glyphWidth = Int(metrics.glyphWidth)
    glyphHeight = Int(metrics.glyphHeight)
    // The texture cells must fit the bitmap even though readable text advances
    // by fewer pixels to provide tighter visual spacing.
    cellWidth = glyphWidth + Int(metrics.glyphSpacing)
    width = Int(Self.lastScalar - Self.firstScalar + 1) * cellWidth
    height = glyphHeight

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let fallback = Font20x28.glyphs[UInt32(Character("?").asciiValue!)] ?? Glyph()

    for scalar in Self.firstScalar...Self.lastScalar {
      let glyph = Font20x28.glyphs[scalar] ?? fallback
      let xOffset = Int(scalar - Self.firstScalar) * cellWidth
      for y in 0..<glyphHeight {
        let bits = glyph.rows[y]
        for x in 0..<glyphWidth
        where bits & (UInt32(1) << UInt32(glyphWidth - x - 1)) != 0 {
          let offset = (y * width + xOffset + x) * 4
          pixels[offset] = 255
          pixels[offset + 1] = 255
          pixels[offset + 2] = 255
          pixels[offset + 3] = 255
        }
      }
    }
    self.pixels = pixels
  }

  static func scalar(for character: Character) -> UInt32 {
    guard character.unicodeScalars.count == 1,
      let value = character.unicodeScalars.first?.value,
      value >= firstScalar,
      value <= lastScalar
    else {
      return 63 // "?"
    }
    return value
  }
}

#endif
