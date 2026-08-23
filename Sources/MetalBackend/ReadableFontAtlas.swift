#if METAL_BACKEND

import AppKit
import Chroma
import CoreGraphics
import CoreText
import Metal

/// A conventional system-monospaced face rasterized into Chroma's fixed cells.
/// The atlas uses grayscale coverage, so the Metal shader can smooth edges while
/// keeping layout and terminal column math identical to the bitmap display face.
struct ReadableFontAtlas {
  let texture: MTLTexture

  private let rasterScale = 2
  private let glyphWidth = Int(FontMetrics().glyphWidth) * 2
  private let glyphHeight = Int(FontMetrics().glyphHeight) * 2
  private let columns = 16
  private let firstScalar: UInt32 = 0x20
  private let lastScalar: UInt32 = 0x7E

  private var characterCount: Int { Int(lastScalar - firstScalar + 1) }
  private var rows: Int { (characterCount + columns - 1) / columns }
  private var atlasWidth: Int { columns * glyphWidth }
  private var atlasHeight: Int { rows * glyphHeight }

  init(device: MTLDevice) throws {
    let width = columns * glyphWidth
    let height = ((Int(lastScalar - firstScalar + 1) + columns - 1) / columns) * glyphHeight
    var pixels = [UInt8](repeating: 0, count: width * height)

    guard
      let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else {
      throw BackendError.initializationFailed(
        backend: "Metal", stage: "readable font atlas",
        reason: "failed to create the atlas drawing context")
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.setShouldSmoothFonts(true)
    context.setFillColor(gray: 1, alpha: 1)
    context.textMatrix = .identity

    // Rasterize at 2× and downsample in Metal. This preserves the requested
    // large size while avoiding the stair-stepped, fuzzy 20 px source atlas.
    let fontSize = CGFloat(20 * rasterScale)
    let systemFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)
    let font = CTFontCreateWithName(systemFont.fontName as CFString, fontSize, nil)
    let ascent = CTFontGetAscent(font)
    let descent = CTFontGetDescent(font)
    let baseline = (CGFloat(glyphHeight) - (ascent + descent)) / 2 + descent

    for value in firstScalar...lastScalar {
      guard let scalar = UnicodeScalar(value) else { continue }
      let string = String(Character(scalar))
      let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): NSColor.white,
      ]
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: string, attributes: attributes))
      let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
      let index = Int(value - firstScalar)
      let cellX = CGFloat((index % columns) * glyphWidth)
      let cellY = CGFloat((index / columns) * glyphHeight)
      let x = cellX + (CGFloat(glyphWidth) - bounds.width) / 2 - bounds.minX
      // CGContext's text origin is bottom-up even though the bitmap rows are
      // consumed top-down by Metal; flip each baseline into its atlas row.
      let y = CGFloat(height) - cellY - CGFloat(glyphHeight) + baseline
      context.textPosition = CGPoint(x: x, y: y)
      CTLineDraw(line, context)
    }

    let descriptor = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw BackendError.initializationFailed(
        backend: "Metal", stage: "readable font atlas",
        reason: "failed to allocate the atlas texture")
    }
    pixels.withUnsafeBytes { bytes in
      texture.replace(
        region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
        withBytes: bytes.baseAddress!, bytesPerRow: width)
    }
    self.texture = texture
  }

  func contains(_ character: Character) -> Bool {
    guard character.unicodeScalars.count == 1,
      let scalar = character.unicodeScalars.first?.value
    else { return false }
    return (firstScalar...lastScalar).contains(scalar)
  }

  func glyphUV(_ character: Character) -> (Float, Float, Float, Float) {
    let scalar = character.unicodeScalars.count == 1 ? character.unicodeScalars.first!.value : 0x3F
    let value = contains(character) ? scalar : 0x3F
    let index = Int(value - firstScalar)
    let x = (index % columns) * glyphWidth
    let y = (index / columns) * glyphHeight
    return (
      Float(x) / Float(atlasWidth), Float(y) / Float(atlasHeight),
      Float(x + glyphWidth) / Float(atlasWidth),
      Float(y + glyphHeight) / Float(atlasHeight)
    )
  }
}

#endif
