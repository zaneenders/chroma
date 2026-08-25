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
      mipmapped: true
    )
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw BackendError.initializationFailed(
        backend: "Metal",
        stage: "font atlas",
        reason: "failed to allocate the atlas texture"
      )
    }
    for (level, mip) in atlas.mipLevels().enumerated() {
      mip.pixels.withUnsafeBytes { bytes in
        texture.replace(
          region: MTLRegionMake2D(0, 0, mip.width, mip.height),
          mipmapLevel: level,
          withBytes: bytes.baseAddress!,
          bytesPerRow: mip.width
        )
      }
    }
    self.texture = texture
    self.atlas = atlas
  }

  func glyphUV(
    _ character: Character, readable: Bool = false
  ) -> (Float, Float, Float, Float) {
    atlas.glyphUV(character, readable: readable)
  }
}

#elseif METAL_TRAIT
#error("The Metal backend requires macOS.")
#endif
