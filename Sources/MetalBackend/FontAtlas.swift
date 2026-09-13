import Chroma
import ChromaFont
import Metal

struct FontAtlas {
  let texture: MTLTexture
  let atlas: HighResolutionFontAtlas

  @MainActor init(device: MTLDevice) throws {
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
      MetalUpload.replace(
        texture, bytes: mip.pixels.span.bytes, width: mip.width, height: mip.height,
        bytesPerPixel: 1, level: level)
    }
    self.texture = texture
    self.atlas = atlas
  }

  func glyphUV(
    _ character: Character
  ) -> (Float, Float, Float, Float) {
    atlas.glyphUV(character)
  }
}
