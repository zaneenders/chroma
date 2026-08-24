#if METAL_BACKEND

import ChromaFont
import Metal

struct FontAtlas {
  let texture: MTLTexture
  let atlas: HighResolutionFontAtlas

  init(device: MTLDevice) throws {
    let atlas = HighResolutionFontAtlas()
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r8Unorm,
      width: atlas.width,
      height: atlas.height,
      mipmapped: false
    )
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw BackendError.initializationFailed(
        backend: "Metal",
        stage: "font atlas",
        reason: "failed to allocate the atlas texture"
      )
    }
    atlas.pixels.withUnsafeBytes { bytes in
      texture.replace(
        region: MTLRegionMake2D(0, 0, atlas.width, atlas.height),
        mipmapLevel: 0,
        withBytes: bytes.baseAddress!,
        bytesPerRow: atlas.width
      )
    }
    self.texture = texture
    self.atlas = atlas
  }

  func glyphUV(_ character: Character) -> (Float, Float, Float, Float) {
    atlas.glyphUV(character)
  }
}

#elseif METAL_TRAIT
#error("The Metal backend requires macOS.")
#endif
