#if METAL_BACKEND

import Chroma
import Metal

struct FontAtlas {
  let texture: MTLTexture

  let glyphWidth: Int = Int(FontMetrics().glyphWidth)
  let glyphHeight: Int = Int(FontMetrics().glyphHeight)
  let glyphSpacing: Int = Int(FontMetrics().glyphSpacing)
  let columns = 16
  let characters: [UInt32]
  let characterIndices: [UInt32: Int]

  var charCount: Int { characters.count }
  var rows: Int { (charCount + columns - 1) / columns }
  var cellWidth: Int { glyphWidth + glyphSpacing }
  var atlasWidth: Int { columns * cellWidth }
  var atlasHeight: Int { rows * glyphHeight }

  init(device: MTLDevice) {
    let metrics = FontMetrics()
    let glyphWidth = Int(metrics.glyphWidth)
    let glyphHeight = Int(metrics.glyphHeight)
    let glyphSpacing = Int(metrics.glyphSpacing)
    let columns = 16
    let characters = Font20x28.glyphs.keys.sorted()
    let characterIndices = Dictionary(
      uniqueKeysWithValues: characters.enumerated().map { ($0.element, $0.offset) })
    let atlasRows = (characters.count + columns - 1) / columns
    let cellWidth = glyphWidth + glyphSpacing
    let width = columns * cellWidth
    let height = atlasRows * glyphHeight
    var pixels = [UInt8](repeating: 0, count: width * height)

    for (index, character) in characters.enumerated() {
      guard let glyph = Font20x28.glyphs[character] else {
        fatalError("Missing bitmap for font character U+\(String(character, radix: 16, uppercase: true))")
      }
      let xOffset = (index % columns) * cellWidth
      let yOffset = (index / columns) * glyphHeight
      let cleanedRows = Self.closingPinholes(in: glyph.rows, width: glyphWidth)
      for y in 0..<glyphHeight {
        let bits = cleanedRows[y]
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
    self.characters = characters
    self.characterIndices = characterIndices
  }

  private static func closingPinholes(in rows: [UInt32], width: Int) -> [UInt32] {
    guard !rows.isEmpty, width > 0 else { return rows }
    let height = rows.count
    var visited = [Bool](repeating: false, count: width * height)
    var result = rows

    func isFilled(_ x: Int, _ y: Int) -> Bool {
      rows[y] & (UInt32(1) << UInt32(width - x - 1)) != 0
    }

    for startY in 0..<height {
      for startX in 0..<width {
        let start = startY * width + startX
        guard !visited[start], !isFilled(startX, startY) else { continue }

        var queue = [(startX, startY)]
        var cursor = 0
        var component: [(Int, Int)] = []
        var touchesEdge = false
        visited[start] = true

        while cursor < queue.count {
          let (x, y) = queue[cursor]
          cursor += 1
          component.append((x, y))
          touchesEdge = touchesEdge || x == 0 || x == width - 1 || y == 0 || y == height - 1

          for (nextX, nextY) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
            guard nextX >= 0, nextX < width, nextY >= 0, nextY < height else { continue }
            let next = nextY * width + nextX
            guard !visited[next], !isFilled(nextX, nextY) else { continue }
            visited[next] = true
            queue.append((nextX, nextY))
          }
        }

        if !touchesEdge, component.count <= 8 {
          for (x, y) in component {
            result[y] |= UInt32(1) << UInt32(width - x - 1)
          }
        }
      }
    }
    return result
  }

  func glyphUV(_ character: Character) -> (Float, Float, Float, Float) {
    let value = character.unicodeScalars.count == 1 ? character.unicodeScalars.first!.value : 0x20
    let index = characterIndices[value] ?? characterIndices[0x20]!
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
