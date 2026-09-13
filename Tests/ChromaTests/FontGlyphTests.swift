import Chroma
import Foundation
import Testing

@testable import ChromaFont

@Suite("Backend-neutral font glyphs")
struct FontGlyphTests {
  @Test func rejectsMalformedAtlasResources() throws {
    #expect(throws: (any Error).self) {
      _ = try HighResolutionFontAtlas(data: Data([0, 1, 2]))
    }
    let atlas = HighResolutionFontAtlas()
    var valid = Data()
    func word(_ value: UInt32) {
      for shift in stride(from: 0, to: 32, by: 8) { valid.append(UInt8(truncatingIfNeeded: value >> shift)) }
    }
    for value: UInt32 in [0x4C54_4143, 1, UInt32(atlas.width), UInt32(atlas.height), 1, 0xFFFD] { word(value) }
    for level in atlas.mipLevels() { valid.append(contentsOf: level.pixels) }
    _ = try HighResolutionFontAtlas(data: valid)
    for cut in [0, 4, 19, 23, valid.count - 1] {
      #expect(throws: HighResolutionFontAtlas.AssetError.self) {
        _ = try HighResolutionFontAtlas(data: Data(valid.prefix(cut)))
      }
    }
    for (offset, value): (Int, UInt32) in [
      (0, 0), (4, 2), (8, 0), (12, 4097), (16, UInt32.max), (20, 0xD800), (20, 65),
    ] {
      var corrupt = valid
      for i in 0..<4 { corrupt[offset + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
      #expect(throws: HighResolutionFontAtlas.AssetError.self) {
        _ = try HighResolutionFontAtlas(data: corrupt)
      }
    }
    #expect(throws: HighResolutionFontAtlas.AssetError.self) {
      _ = try HighResolutionFontAtlas(data: valid + Data([0]))
    }
  }

  private func fixture(scalars: [UInt32] = [0xFFFD]) -> (Data, [[UInt8]]) {
    var data = Data()
    for value: UInt32 in [0x4C54_4143, 1, 2112, 90, UInt32(scalars.count)] + scalars {
      for shift in stride(from: 0, to: 32, by: 8) {
        data.append(UInt8(truncatingIfNeeded: value >> shift))
      }
    }
    var levels: [[UInt8]] = []
    var width = 2112
    var height = 90
    while true {
      let pixels = (0..<(width * height)).map { UInt8(truncatingIfNeeded: $0 + levels.count) }
      levels.append(pixels)
      data.append(contentsOf: pixels)
      if width == 1 && height == 1 { break }
      width = max(1, width / 2)
      height = max(1, height / 2)
    }
    return (data, levels)
  }

  @Test func borrowedAtlasSupportsSlicesAndOwnsItsMipPixels() throws {
    let (data, pixels) = fixture()
    var padded = Data([0xAA])
    padded.append(data)
    var slice = padded.dropFirst()
    #expect(slice.startIndex == 1)
    let atlas = try HighResolutionFontAtlas(data: slice)
    slice.resetBytes(in: slice.startIndex..<slice.endIndex)
    #expect(atlas.width == 2112)
    #expect(atlas.height == 90)
    #expect(atlas.characterIndices == [0xFFFD: 0])
    #expect(atlas.mipLevels().map(\.pixels) == pixels)
  }

  @Test func borrowedAtlasRejectsTruncatedWordsAndMipLevels() {
    let (data, levels) = fixture()
    var cuts = Array(0..<24)
    var cursor = 24
    for pixels in levels {
      cuts.append(cursor)
      cursor += pixels.count
      cuts.append(cursor - 1)
    }
    for cut in cuts {
      #expect(throws: HighResolutionFontAtlas.AssetError.self) {
        _ = try HighResolutionFontAtlas(data: Data(data.prefix(cut)))
      }
    }
  }

  @Test func borrowedAtlasRejectsDuplicateScalars() {
    let (data, _) = fixture(scalars: [0xFFFD, 0xFFFD])
    #expect(throws: HighResolutionFontAtlas.AssetError.self) {
      _ = try HighResolutionFontAtlas(data: data)
    }
  }

  @Test func coversTerminalStructureAndPromptSymbols() {
    let required: [UInt32] = [
      0x2500,
      0x256D,
      0x2588,
      0x2801,
      0x279C,
      0x2717,
      0xE0B0,
      0xFFFD,
    ]
    for codepoint in required {
      #expect(HighResolutionFontAtlas().characterIndices[codepoint] != nil)
    }
  }

  @Test func coversKeyboardAndInterfaceSymbols() {
    let required: [UInt32] = [
      0x2318,
      0x2325,
      0x2303,
      0x21E7,
      0x21B5,
      0x2302,
      0x25A0,
      0x25C7,
      0x270E,
      0x23F5,
      0x23F9,
    ]
    for codepoint in required {
      #expect(HighResolutionFontAtlas().characterIndices[codepoint] != nil)
    }
  }

  @Test func generatedSymbolsFitTheTextAdvance() {
    let atlas = HighResolutionFontAtlas()
    let advance = Int(FontMetrics().cellAdvance) * HighResolutionFontAtlas.scale
    #expect(advance == 36)
    for scalar in atlas.characterIndices.keys where scalar >= 0x250 {
      let index = atlas.characterIndices[scalar]!
      let x = (index % HighResolutionFontAtlas.columns) * atlas.cellWidth + HighResolutionFontAtlas.padding
      let y = (index / HighResolutionFontAtlas.columns) * atlas.cellHeight + HighResolutionFontAtlas.padding
      for row in 0..<atlas.glyphHeight {
        let start = (y + row) * atlas.width + x
        #expect(atlas.pixels[(start + advance)..<(start + atlas.glyphWidth)].allSatisfy { $0 == 0 })
        if scalar == 0x2588 {
          #expect(atlas.pixels[start..<(start + advance)].allSatisfy { $0 == 255 })
        }
        if scalar == 0x2500 {
          #expect(atlas.pixels[start] == atlas.pixels[start + advance - 1])
          #expect(atlas.pixels[start] == ((39..<45).contains(row) ? 255 : 0))
        }
      }
    }
  }

  @Test func coversPrintableASCII() {
    let atlas = HighResolutionFontAtlas()
    for codepoint in UInt32(0x20)...UInt32(0x7E) {
      #expect(atlas.characterIndices[codepoint] != nil)
    }
  }

  @Test func bundledPixelsRemainUnchanged() {
    let atlas = HighResolutionFontAtlas()
    #expect(atlas.characterIndices.count == 762)
    var hash: UInt64 = 14_695_981_039_346_656_037
    for scalar in atlas.characterIndices.sorted(by: { $0.value < $1.value }).map(\.key) {
      for shift in stride(from: 0, to: 32, by: 8) {
        hash = (hash ^ UInt64(UInt8(truncatingIfNeeded: scalar >> shift))) &* 1_099_511_628_211
      }
    }
    for level in atlas.mipLevels() {
      for pixel in level.pixels { hash = (hash ^ UInt64(pixel)) &* 1_099_511_628_211 }
    }
    #expect(hash == 999_759_037_810_430_912)
    let uv = atlas.glyphUV(" ")
    let x = Int((uv.0 * Float(atlas.width)).rounded())
    let y = Int((uv.1 * Float(atlas.height)).rounded())
    for row in 0..<atlas.glyphHeight {
      #expect(
        atlas.pixels[((y + row) * atlas.width + x)..<((y + row) * atlas.width + x + atlas.glyphWidth)].allSatisfy {
          $0 == 0
        })
    }
  }

  @Test func highResolutionAtlasSharesCoverageAndMappingAcrossBackends() {
    let atlas = HighResolutionFontAtlas()
    #expect(atlas.glyphWidth == 60)
    #expect(atlas.glyphHeight == 84)
    #expect(atlas.pixels.count == atlas.width * atlas.height)
    #expect(atlas.pixels.contains(0))
    #expect(atlas.pixels.contains(255))
    #expect(atlas.pixels.contains { $0 > 0 && $0 < 255 })

    let a = atlas.glyphUV("A")
    let b = atlas.glyphUV("B")
    let fallback = atlas.glyphUV("�")
    #expect(a != b)
    #expect(atlas.glyphUV("🙂") == fallback)
    #expect(a.0 >= 0 && a.1 >= 0 && a.2 <= 1 && a.3 <= 1)
  }

  @Test func atlasFitsGuaranteedGLES3TextureDimensions() {
    let atlas = HighResolutionFontAtlas()
    let guaranteedMaximumTextureSize = 4096
    #expect(atlas.width > 0 && atlas.width <= guaranteedMaximumTextureSize)
    #expect(atlas.height > 0 && atlas.height <= guaranteedMaximumTextureSize)
  }

  @Test func latinAccentsShareCellsAcrossCanonicalSpellings() {
    let atlas = HighResolutionFontAtlas()
    let accented = atlas.characterIndices.keys.filter {
      (0xC0..<0x250).contains($0)
        && String(UnicodeScalar($0)!).decomposedStringWithCanonicalMapping.unicodeScalars.count == 2
    }
    #expect(accented.count == 190)
    for scalar in accented {
      let spelling = String(UnicodeScalar(scalar)!)
      let composed = Character(spelling)
      let decomposition = spelling.decomposedStringWithCanonicalMapping
      let decomposed = Character(decomposition)
      let base = Character(String(decomposition.unicodeScalars.first!))
      let uv = atlas.glyphUV(composed)
      #expect(uv == atlas.glyphUV(decomposed))
      #expect(uv != atlas.glyphUV("�"))
      #expect(uv != atlas.glyphUV(base))
      #expect(uv.0 >= 0 && uv.1 >= 0 && uv.2 <= 1 && uv.3 <= 1)
      let x = Int((uv.0 * Float(atlas.width)).rounded())
      let y = Int((uv.1 * Float(atlas.height)).rounded())
      let ink = (0..<atlas.glyphHeight).reduce(0) { total, row in
        total
          + atlas.pixels[((y + row) * atlas.width + x)..<((y + row) * atlas.width + x + atlas.glyphWidth)]
          .filter { $0 != 0 }.count
      }
      #expect(ink > 0)

    }
  }

  @Test func unsupportedClustersAreNotSilentlyStripped() {
    let atlas = HighResolutionFontAtlas()
    let fallback = atlas.glyphUV("�")
    for character: Character in ["e\u{0301}\u{0308}", "e\u{0338}", "\u{0301}", "👩‍💻", "🇺🇸"] {
      #expect(atlas.glyphUV(character) == fallback)
    }

  }

  @Test func accentedTextKeepsMonospaceMeasurement() {
    let metrics = FontMetrics()
    #expect(metrics.measure("café") == metrics.measure("cafe"))
    #expect(metrics.measure("cafe\u{0301}") == metrics.measure("café"))

  }

  @Test func atlasMipmapsPreserveCoverageWhileReducingForGPUOutput() {
    let atlas = HighResolutionFontAtlas()
    let levels = atlas.mipLevels()

    #expect(levels.first?.width == atlas.width)
    #expect(levels.first?.height == atlas.height)
    #expect(levels.first?.pixels == atlas.pixels)
    #expect(levels.last?.width == 1)
    #expect(levels.last?.height == 1)

    for (parent, child) in zip(levels, levels.dropFirst()) {
      #expect(child.width == max(1, parent.width / 2))
      #expect(child.height == max(1, parent.height / 2))
      #expect(child.pixels.count == child.width * child.height)
    }

    #expect(
      levels.dropFirst().contains { level in
        level.pixels.contains { $0 > 0 && $0 < 255 }
      })
  }

}
