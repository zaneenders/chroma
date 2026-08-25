import ChromaFont
import Testing

@Suite("Backend-neutral font glyphs")
struct FontGlyphTests {
  private var glyphs: [UInt32: Glyph] {
    Font20x28.glyphs.merging(GlyphGenerator.generated) { authored, _ in authored }
  }

  @Test func allGlyphsAreValidTwentyByTwentyEightBitmaps() {
    #expect(!glyphs.isEmpty)
    for glyph in glyphs.values {
      #expect(glyph.rows.count == 28)
      #expect(glyph.rows.allSatisfy { $0 < (1 << 20) })
    }
  }

  @Test func shadeGlyphsHaveStandardCoverage() {
    let pixelCount = 20 * 28
    #expect(glyphs[0x2591]?.rows.reduce(0) { $0 + $1.nonzeroBitCount } == pixelCount / 4)
    #expect(glyphs[0x2592]?.rows.reduce(0) { $0 + $1.nonzeroBitCount } == pixelCount / 2)
    #expect(glyphs[0x2593]?.rows.reduce(0) { $0 + $1.nonzeroBitCount } == pixelCount * 3 / 4)
  }

  @Test func coversTerminalStructureAndPromptSymbols() {
    let required: [UInt32] = [
      0x2500,  // ─ box drawing
      0x256D,  // ╭ rounded corner
      0x2588,  // █ block
      0x2801,  // ⠁ braille
      0x279C,  // ➜ prompt
      0x2717,  // ✗ dirty marker
      0xE0B0,  // Powerline separator
      0xFFFD,  // visible unsupported-glyph fallback
    ]
    for codepoint in required {
      #expect(glyphs[codepoint] != nil)
    }
  }

  @Test func coversKeyboardAndInterfaceSymbols() {
    let required: [UInt32] = [
      0x2318,  // ⌘ Command
      0x2325,  // ⌥ Option
      0x2303,  // ⌃ Control
      0x21E7,  // ⇧ Shift
      0x21B5,  // ↵ Return
      0x2302,  // ⌂ Home/folder
      0x25A0,  // ■ Stop
      0x25C7,  // ◇ Outline diamond
      0x23F5,  // ⏵ Play
      0x23F9,  // ⏹ Stop control
    ]
    for codepoint in required {
      #expect(glyphs[codepoint] != nil)
    }
  }

  @Test func coversPrintableASCII() {
    for codepoint in UInt32(0x20)...UInt32(0x7E) {
      #expect(glyphs[codepoint] != nil)
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
    #expect(atlas.glyphUV("A", readable: true) != a)
    let fallback = atlas.glyphUV("�")
    #expect(a != b)
    #expect(atlas.glyphUV("🙂") == fallback)
    #expect(a.0 >= 0 && a.1 >= 0 && a.2 <= 1 && a.3 <= 1)
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

    // Filtering binary glyph coverage must produce intermediate edge samples;
    // otherwise minified GPU text would still have hard, unstable stair steps.
    #expect(levels.dropFirst().contains { level in
      level.pixels.contains { $0 > 0 && $0 < 255 }
    })
  }

  @Test func roundedCornersConnectTheSameEdgesAsTheirSquareEquivalents() throws {
    // ╭ ╮ ╯ ╰ must open toward the same cell edges as ┌ ┐ ┘ └: a "down"
    // corner keeps all ink in the bottom half and touches the bottom edge,
    // an "up" corner the top half and top edge, and left/right likewise.
    // Regresses a vertical flip that rendered ╭ as ╰.
    func rowHasInk(_ glyph: Glyph, _ y: Int) -> Bool { glyph.rows[y] != 0 }
    func columnHasInk(_ glyph: Glyph, _ x: Int) -> Bool {
      (0..<28).contains { glyph.rows[$0] & (1 << (19 - x)) != 0 }
    }

    let downRight = try #require(glyphs[0x256D])  // ╭
    let downLeft = try #require(glyphs[0x256E])  // ╮
    let upLeft = try #require(glyphs[0x256F])  // ╯
    let upRight = try #require(glyphs[0x2570])  // ╰

    // The middle band is rows 13...14; the 2px brush may spill one row past
    // it, so the empty halves are asserted with one row of slack.
    for (glyph, name) in [(downRight, "╭"), (downLeft, "╮")] {
      for y in 0...11 {
        #expect(!rowHasInk(glyph, y), "\(name) must not ink row \(y) above the middle band")
      }
      #expect(rowHasInk(glyph, 27), "\(name) must touch the bottom edge")
    }
    for (glyph, name) in [(upLeft, "╯"), (upRight, "╰")] {
      for y in 16...27 {
        #expect(!rowHasInk(glyph, y), "\(name) must not ink row \(y) below the middle band")
      }
      #expect(rowHasInk(glyph, 0), "\(name) must touch the top edge")
    }

    #expect(columnHasInk(downRight, 19) && !columnHasInk(downRight, 0))  // ╭ opens right, not left
    #expect(columnHasInk(downLeft, 0) && !columnHasInk(downLeft, 19))  // ╮
    #expect(columnHasInk(upLeft, 0) && !columnHasInk(upLeft, 19))  // ╯
    #expect(columnHasInk(upRight, 19) && !columnHasInk(upRight, 0))  // ╰
  }
}
