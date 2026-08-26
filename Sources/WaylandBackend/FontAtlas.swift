#if WAYLAND_BACKEND

import ChromaFont

/// Holds the shared single-channel coverage atlas and its prefiltered mip chain
/// for the GLES texture path.
struct FontAtlas {
  let shared: HighResolutionFontAtlas
  let mipLevels: [FontAtlasMipLevel]

  var width: Int { shared.width }
  var height: Int { shared.height }

  init() {
    let shared = HighResolutionFontAtlas()
    self.shared = shared
    mipLevels = shared.mipLevels()
  }

  func glyphUV(
    _ character: Character, readable: Bool = false
  ) -> (Float, Float, Float, Float) {
    shared.glyphUV(character, readable: readable)
  }
}

#endif
