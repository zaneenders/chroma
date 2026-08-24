#if WAYLAND_BACKEND

import ChromaFont

/// Converts the shared single-channel atlas to RGBA for the GLES texture path.
/// Coverage lives in alpha; RGB stays white so the renderer can tint glyphs.
struct FontAtlas {
  let shared: HighResolutionFontAtlas
  let pixels: [UInt8]

  var width: Int { shared.width }
  var height: Int { shared.height }

  init() {
    let shared = HighResolutionFontAtlas()
    var pixels = [UInt8](repeating: 255, count: shared.pixels.count * 4)
    for (index, coverage) in shared.pixels.enumerated() {
      pixels[index * 4 + 3] = coverage
    }
    self.shared = shared
    self.pixels = pixels
  }

  func glyphUV(_ character: Character) -> (Float, Float, Float, Float) {
    shared.glyphUV(character)
  }
}

#endif
