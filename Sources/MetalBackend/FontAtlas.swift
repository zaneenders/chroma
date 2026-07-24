#if METAL_BACKEND

import Chroma
import Metal

struct FontAtlas {
  let texture: MTLTexture

  // FontMetrics is the single source of truth for glyph geometry.
  let glyphWidth: Int = Int(FontMetrics().glyphWidth)
  let glyphHeight: Int = Int(FontMetrics().glyphHeight)
  let glyphSpacing: Int = Int(FontMetrics().glyphSpacing)
  let firstChar: UInt8 = 32
  let lastChar: UInt8 = 126
  let columns = 16

  var charCount: Int { Int(lastChar - firstChar + 1) }
  var rows: Int { (charCount + columns - 1) / columns }
  var cellWidth: Int { glyphWidth + glyphSpacing }
  var atlasWidth: Int { columns * cellWidth }
  var atlasHeight: Int { rows * glyphHeight }

  init(device: MTLDevice) {
    let metrics = FontMetrics()
    let glyphWidth = Int(metrics.glyphWidth)
    let glyphHeight = Int(metrics.glyphHeight)
    let glyphSpacing = Int(metrics.glyphSpacing)
    let firstChar: UInt8 = 32
    let lastChar: UInt8 = 126
    let columns = 16
    let count = Int(lastChar - firstChar + 1)
    let atlasRows = (count + columns - 1) / columns
    let cellWidth = glyphWidth + glyphSpacing
    let width = columns * cellWidth
    let height = atlasRows * glyphHeight
    var pixels = [UInt8](repeating: 0, count: width * height)

    for byte in firstChar...lastChar {
      guard let glyph = Font20x28.glyphs[byte] else {
        fatalError("Missing bitmap for printable ASCII character 0x\(String(byte, radix: 16))")
      }
      let index = Int(byte - firstChar)
      let xOffset = (index % columns) * cellWidth
      let yOffset = (index / columns) * glyphHeight
      for y in 0..<glyphHeight {
        let bits = glyph.rows[y]
        for x in 0..<glyphWidth where bits & (UInt32(1) << UInt32(glyphWidth - x - 1)) != 0 {
          pixels[(yOffset + y) * width + xOffset + x] = 255
        }
      }
    }

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r8Unorm,
      width: width,
      height: height,
      mipmapped: false
    )
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      fatalError("Failed to create font atlas texture")
    }
    pixels.withUnsafeBytes { bytes in
      texture.replace(
        region: MTLRegionMake2D(0, 0, width, height),
        mipmapLevel: 0,
        withBytes: bytes.baseAddress!,
        bytesPerRow: width
      )
    }
    self.texture = texture
  }

  func glyphUV(_ byte: UInt8) -> (Float, Float, Float, Float) {
    let character = (firstChar...lastChar).contains(byte) ? byte : firstChar
    let index = Int(character - firstChar)
    let x = (index % columns) * cellWidth
    let y = (index / columns) * glyphHeight
    return (
      Float(x) / Float(atlasWidth),
      Float(y) / Float(atlasHeight),
      Float(x + glyphWidth) / Float(atlasWidth),
      Float(y + glyphHeight) / Float(atlasHeight)
    )
  }
}

#elseif METAL_TRAIT
#error("The Metal backend requires macOS.")
#endif
