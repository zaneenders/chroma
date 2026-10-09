import ChromaTesting
import Testing

@testable import Chroma

struct FontMetricsTests {
  @Test(arguments: ["\n", "\r\n", "\r", "\u{000b}", "\u{000c}", "\u{0085}", "\u{2028}", "\u{2029}"])
  func measurementMatchesLayoutNewlines(newline: String) {
    var metrics = FontMetrics()
    metrics.cellAdvance = 9
    metrics.glyphHeight = 15
    metrics.lineAdvance = 21
    let text = "👨‍👩‍👧‍👦e\u{301}\(newline)\(newline)界\(newline)"
    let layout = TextLayout(text)

    #expect(layout.lines.map(\.text) == ["👨‍👩‍👧‍👦e\u{301}", "", "界", ""])
    #expect(layout.lines.map(\.range) == [0..<2, 3..<3, 4..<5, 6..<6])
    #expect(metrics.measure(text, scale: 2) == Size(width: 36, height: 156))
  }

  @Test func measurementPreservesEmptyAndSingleLineDimensions() {
    let metrics = FontMetrics()
    #expect(metrics.measure("") == Size(width: 0, height: 28))
    #expect(metrics.measure("👨‍👩‍👧‍👦e\u{301}", scale: 1.5) == Size(width: 36, height: 42))
    #expect(metrics.measure("a\nbbbb") == Size(width: 48, height: 60))
    #expect(metrics.measure("\n\r\n\r\u{2028}") == Size(width: 0, height: 156))
  }

  @Test(arguments: ["\n", "\r\n", "\r", "\u{2028}"], [false, true])
  @MainActor func followingStackRowStartsBelowAllTextLines(newline: String, selectable: Bool) {
    let host = HeadlessHost(size: Size(width: 100, height: 100))
    defer { host.close() }
    host.build = { buffer, context in
      let text = Text("a\(newline)b")
      let first = buffer.text(selectable ? text.selectable() : text, context: context.keyed(0))
      let second = buffer.text(Text("c"), context: context.keyed(1))
      return buffer.stack([first, second], axis: .vertical, context: context)
    }

    // Repeat the frame to cover both newly shaped and cached text layouts.
    for _ in 0..<2 {
      let glyphs = host.render().commands.compactMap { entry -> Rect? in
        if case .quad(let quad) = entry, quad.texture == .fontAtlas { return quad.rect }
        return nil
      }
      #expect(glyphs.map(\.minY) == [0, 32, 60])
      #expect(glyphs.count == 3)
      if glyphs.count == 3 {
        #expect(glyphs[2].minY >= glyphs[1].maxY)
      }
    }
  }
}
