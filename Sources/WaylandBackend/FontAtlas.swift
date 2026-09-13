#if WAYLAND_BACKEND

import ChromaFont

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
    _ character: Character
  ) -> (Float, Float, Float, Float) {
    shared.glyphUV(character)
  }
}

#endif
