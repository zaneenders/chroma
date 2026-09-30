import Foundation
import Synchronization
import Testing

@testable import ChromaFont

struct MissingGlyphWarningTests {
  @Test func reportsEveryMissingCharacterAcrossConcurrentRequests() async {
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings { line in lines.withLock { $0.append(line) } }
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<100 {
        group.addTask { warnings.report("🙂") }
      }
    }
    #expect(lines.withLock { $0.count } == 100)
    #expect(lines.withLock { $0.allSatisfy { $0 == "[warning] chroma.font.missing-glyph codepoints=U+1F642\n" } })
  }

  @Test func reportsAllScalarsWithoutLoggingSurroundingText() {
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings { line in lines.withLock { $0.append(line) } }
    warnings.report("👩‍💻")
    warnings.report("🙂")
    #expect(
      lines.withLock { $0 } == [
        "[warning] chroma.font.missing-glyph codepoints=U+1F469,U+200D,U+1F4BB\n",
        "[warning] chroma.font.missing-glyph codepoints=U+1F642\n",
      ])
  }
}
