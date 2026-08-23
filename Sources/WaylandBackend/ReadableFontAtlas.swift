#if WAYLAND_BACKEND

import CFontconfig
import CFreeType
import Chroma

/// A system monospace font rasterized directly at the size used by the GLES
/// renderer. Unlike the display font, these glyphs use grayscale coverage and
/// do not enlarge a small bitmap atlas.
struct ReadableFontAtlas {
  static let firstScalar: UInt32 = 0x20
  static let lastScalar: UInt32 = 0x7E

  let width: Int
  let height: Int
  let glyphWidth: Int
  let glyphHeight: Int
  let pixels: [UInt8]

  init(metrics: FontMetrics = FontMetrics()) throws {
    glyphWidth = Int(metrics.glyphWidth)
    glyphHeight = Int(metrics.glyphHeight)
    width = Int(Self.lastScalar - Self.firstScalar + 1) * glyphWidth
    height = glyphHeight

    guard FcInit() != 0 else { throw FontAtlasError("fontconfig initialization failed") }
    guard let pattern = FcNameParse("monospace:weight=bold".withCString {
      UnsafePointer<FcChar8>(OpaquePointer($0))
    }) else { throw FontAtlasError("could not create a monospace font pattern") }
    defer { FcPatternDestroy(pattern) }
    _ = FcConfigSubstitute(nil, pattern, FcMatchPattern)
    FcDefaultSubstitute(pattern)
    var matchResult = FcResultMatch
    guard let match = FcFontMatch(nil, pattern, &matchResult) else {
      throw FontAtlasError("fontconfig could not find a monospace font")
    }
    defer { FcPatternDestroy(match) }
    var file: UnsafeMutablePointer<FcChar8>?
    guard FcPatternGetString(match, FC_FILE, 0, &file) == FcResultMatch, let file else {
      throw FontAtlasError("matched monospace font has no file")
    }

    var library: FT_Library?
    guard FT_Init_FreeType(&library) == 0, let library else {
      throw FontAtlasError("FreeType initialization failed")
    }
    defer { FT_Done_FreeType(library) }
    var face: FT_Face?
    guard FT_New_Face(library, UnsafePointer<CChar>(OpaquePointer(file)), 0, &face) == 0,
      let face
    else { throw FontAtlasError("FreeType could not load the matched font") }
    defer { FT_Done_Face(face) }

    // Match the native 20 pt readable face used by the Metal backend, but
    // rasterize at final resolution so GLES does not scale bitmap glyphs.
    guard FT_Set_Pixel_Sizes(face, 0, FT_UInt(glyphWidth)) == 0 else {
      throw FontAtlasError("FreeType could not set the readable font size")
    }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for scalar in Self.firstScalar...Self.lastScalar {
      guard FT_Load_Char(face, FT_ULong(scalar), Int32(FT_LOAD_RENDER)) == 0,
        let slot = face.pointee.glyph
      else { continue }
      let bitmap = slot.pointee.bitmap
      guard let buffer = bitmap.buffer else { continue }
      let cellX = Int(scalar - Self.firstScalar) * glyphWidth
      let left = (glyphWidth - Int(bitmap.width)) / 2
      // FreeType's bitmap_top is measured upward from the baseline. Center the
      // font's nominal pixel size in Chroma's 28 px line box.
      let baseline = (glyphHeight + glyphWidth) / 2
      let top = baseline - Int(slot.pointee.bitmap_top)
      let pitch = Int(bitmap.pitch)

      for y in 0..<Int(bitmap.rows) {
        let destinationY = top + y
        guard destinationY >= 0, destinationY < glyphHeight else { continue }
        for x in 0..<Int(bitmap.width) {
          let destinationX = cellX + left + x
          guard destinationX >= cellX, destinationX < cellX + glyphWidth else { continue }
          let source = pitch >= 0 ? y * pitch + x : (Int(bitmap.rows) - y - 1) * -pitch + x
          let coverage = buffer[source]
          let offset = (destinationY * width + destinationX) * 4
          pixels[offset] = 255
          pixels[offset + 1] = 255
          pixels[offset + 2] = 255
          pixels[offset + 3] = coverage
        }
      }
    }
    self.pixels = pixels
  }

  func contains(_ character: Character) -> Bool {
    guard character.unicodeScalars.count == 1,
      let scalar = character.unicodeScalars.first?.value
    else { return false }
    return (Self.firstScalar...Self.lastScalar).contains(scalar)
  }

  func uv(for character: Character) -> (Float, Float, Float, Float) {
    let scalar = contains(character) ? character.unicodeScalars.first!.value : UInt32(0x3F)
    let x = Float(scalar - Self.firstScalar) * Float(glyphWidth)
    return (x / Float(width), 0, (x + Float(glyphWidth)) / Float(width), 1)
  }
}

private struct FontAtlasError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

#endif
