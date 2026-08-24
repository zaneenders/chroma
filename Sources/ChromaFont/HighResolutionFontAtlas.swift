/// Backend-neutral 3× grayscale atlas built entirely from Chroma's authored
/// monospaced bitmap glyphs. Metal and Wayland upload identical pixels and do
/// not require bundled third-party fonts or font libraries at runtime.
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
    let rows = (characters.count + Self.columns - 1) / Self.columns
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

    self.characters = characters
    characterIndices = indices
    self.pixels = pixels
    self.width = width
    self.height = height
  }

  public func glyphUV(_ character: Character) -> (Float, Float, Float, Float) {
    let scalar = character.unicodeScalars.count == 1
      ? character.unicodeScalars.first!.value : UInt32(0xFFFD)
    let fallback = characterIndices[0xFFFD] ?? characterIndices[0x3F] ?? 0
    let index = characterIndices[scalar] ?? fallback
    let x = (index % Self.columns) * cellWidth + Self.padding
    let y = (index / Self.columns) * cellHeight + Self.padding
    return (
      Float(x) / Float(width), Float(y) / Float(height),
      Float(x + glyphWidth) / Float(width), Float(y + glyphHeight) / Float(height)
    )
  }
}
