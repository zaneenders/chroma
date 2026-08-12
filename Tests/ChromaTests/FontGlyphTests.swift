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
}
