/// Backend-neutral grayscale atlas. Display and terminal symbols come from
/// Chroma's authored bitmap glyphs; printable readable text comes from an
/// offline rasterization of Bedstead. Backends upload identical pixels and do
/// not require a font library at runtime.
public struct FontAtlasMipLevel: Sendable {
  public let width: Int
  public let height: Int
  public let pixels: [UInt8]
}

public struct HighResolutionFontAtlas: Sendable {
  public static let scale = 3
  public static let columns = 16
  public static let sourceGlyphWidth = 20
  public static let sourceGlyphHeight = 28
  public static let padding = scale

  public let characters: [UInt32]
  public let characterIndices: [UInt32: Int]
  public let pixels: [UInt8]
  public let width: Int
  public let height: Int
  private let readableStartIndex: Int

  public var glyphWidth: Int { Self.sourceGlyphWidth * Self.scale }
  public var glyphHeight: Int { Self.sourceGlyphHeight * Self.scale }
  public var cellWidth: Int { glyphWidth + 2 * Self.padding }
  public var cellHeight: Int { glyphHeight + 2 * Self.padding }

  public init() {
    let generated = GlyphGenerator.generated
    let glyphs = Font20x28.glyphs.merging(generated) { authored, _ in authored }
    let characters = glyphs.keys.sorted()
    let indices = Dictionary(
      uniqueKeysWithValues: characters.enumerated().map { ($0.element, $0.offset) })
    let displayRows = (characters.count + Self.columns - 1) / Self.columns
    let readableCount = Int(BedsteadReadableFont.lastScalar - BedsteadReadableFont.firstScalar + 1)
    let readableStartIndex = displayRows * Self.columns
    let rows = displayRows + (readableCount + Self.columns - 1) / Self.columns
    let cellWidth = Self.sourceGlyphWidth * Self.scale + 2 * Self.padding
    let cellHeight = Self.sourceGlyphHeight * Self.scale + 2 * Self.padding
    let width = Self.columns * cellWidth
    let height = rows * cellHeight
    let glyphWidth = Self.sourceGlyphWidth * Self.scale
    let glyphHeight = Self.sourceGlyphHeight * Self.scale
    var pixels = [UInt8](repeating: 0, count: width * height)

    for scalar in characters {
      guard let index = indices[scalar], let glyph = glyphs[scalar] else { continue }
      let originX = (index % Self.columns) * cellWidth + Self.padding
      let originY = (index / Self.columns) * cellHeight + Self.padding

      for y in 0..<glyphHeight {
        let sourceY = y / Self.scale
        for x in 0..<glyphWidth {
          let sourceX = x / Self.scale
          let mask = UInt32(1) << UInt32(Self.sourceGlyphWidth - sourceX - 1)
          if glyph.rows[sourceY] & mask != 0 {
            pixels[(originY + y) * width + originX + x] = 255
          }
        }
      }
    }

    for offset in 0..<readableCount {
      let index = readableStartIndex + offset
      let originX = (index % Self.columns) * cellWidth + Self.padding
      let originY = (index / Self.columns) * cellHeight + Self.padding
      let sourceOffset = offset * BedsteadReadableFont.glyphWidth * BedsteadReadableFont.glyphHeight
      for y in 0..<BedsteadReadableFont.glyphHeight {
        let sourceRow = sourceOffset + y * BedsteadReadableFont.glyphWidth
        let destinationRow = (originY + y) * width + originX
        pixels.replaceSubrange(
          destinationRow..<(destinationRow + BedsteadReadableFont.glyphWidth),
          with: BedsteadReadableFont.pixels[
            sourceRow..<(sourceRow + BedsteadReadableFont.glyphWidth)])
      }
    }

    self.characters = characters
    characterIndices = indices
    self.pixels = pixels
    self.width = width
    self.height = height
    self.readableStartIndex = readableStartIndex
  }

  /// Builds box-filtered mip levels for the atlas. Supplying these to the GPU
  /// avoids the unstable one-sample-per-fragment result seen when the 3× atlas
  /// is reduced to small UI text.
  public func mipLevels() -> [FontAtlasMipLevel] {
    var levels = [FontAtlasMipLevel(width: width, height: height, pixels: pixels)]
    var source = pixels
    var sourceWidth = width
    var sourceHeight = height

    while sourceWidth > 1 || sourceHeight > 1 {
      let destinationWidth = max(1, sourceWidth / 2)
      let destinationHeight = max(1, sourceHeight / 2)
      var destination = [UInt8](
        repeating: 0, count: destinationWidth * destinationHeight)

      for y in 0..<destinationHeight {
        for x in 0..<destinationWidth {
          var total = 0
          var count = 0
          for sourceY in (y * 2)..<min(y * 2 + 2, sourceHeight) {
            for sourceX in (x * 2)..<min(x * 2 + 2, sourceWidth) {
              total += Int(source[sourceY * sourceWidth + sourceX])
              count += 1
            }
          }
          destination[y * destinationWidth + x] = UInt8((total + count / 2) / count)
        }
      }

      levels.append(
        FontAtlasMipLevel(
          width: destinationWidth, height: destinationHeight, pixels: destination))
      source = destination
      sourceWidth = destinationWidth
      sourceHeight = destinationHeight
    }
    return levels
  }

  public func glyphUV(
    _ character: Character, readable: Bool = false
  ) -> (Float, Float, Float, Float) {
    let scalar = character.unicodeScalars.count == 1
      ? character.unicodeScalars.first!.value : UInt32(0xFFFD)
    let readableRange = BedsteadReadableFont.firstScalar...BedsteadReadableFont.lastScalar
    let index: Int
    if readable, readableRange.contains(scalar) {
      index = readableStartIndex + Int(scalar - BedsteadReadableFont.firstScalar)
    } else {
      let fallback = characterIndices[0xFFFD] ?? characterIndices[0x3F] ?? 0
      index = characterIndices[scalar] ?? fallback
    }
    let x = (index % Self.columns) * cellWidth + Self.padding
    let y = (index / Self.columns) * cellHeight + Self.padding
    return (
      Float(x) / Float(width), Float(y) / Float(height),
      Float(x + glyphWidth) / Float(width), Float(y + glyphHeight) / Float(height)
    )
  }
}
