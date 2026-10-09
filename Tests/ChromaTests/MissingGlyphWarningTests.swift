import Dispatch
import Foundation
import Synchronization
import Testing

@testable import ChromaFont

struct MissingGlyphWarningTests {
  @Test func reportsEveryMissingCharacterAcrossConcurrentRequests() async {
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings(policy: .perOccurrence) { line in lines.withLock { $0.append(line) } }
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<100 {
        group.addTask { warnings.report("🙂") }
      }
    }
    warnings.waitForPendingReports()
    #expect(lines.withLock { $0.count } == 100)
    #expect(lines.withLock { $0.allSatisfy { $0 == "[warning] chroma.font.missing-glyph codepoints=U+1F642\n" } })
  }

  @Test func reportsAllScalarsWithoutLoggingSurroundingText() {
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings(policy: .perOccurrence) { line in lines.withLock { $0.append(line) } }
    warnings.report("👩‍💻")
    warnings.report("🙂")
    warnings.waitForPendingReports()
    #expect(
      lines.withLock { $0 } == [
        "[warning] chroma.font.missing-glyph codepoints=U+1F469,U+200D,U+1F4BB\n",
        "[warning] chroma.font.missing-glyph codepoints=U+1F642\n",
      ])
  }

  @Test func boundedModeDeduplicatesConcurrentRequests() async {
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings { line in lines.withLock { $0.append(line) } }
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<1_000 { group.addTask { warnings.report("🙂") } }
    }
    warnings.waitForPendingReports()
    #expect(lines.withLock { $0 } == ["[warning] chroma.font.missing-glyph codepoints=U+1F642\n"])
  }

  @Test func boundedModeCapsDistinctConcurrentDiagnostics() async {
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings { line in lines.withLock { $0.append(line) } }
    await withTaskGroup(of: Void.self) { group in
      for scalar in 0xF0000..<0xF1000 {
        group.addTask { warnings.report(Character(String(UnicodeScalar(scalar)!))) }
      }
    }
    warnings.waitForPendingReports()
    let result = lines.withLock { $0 }
    #expect(result.count == MissingGlyphWarnings.signatureLimit + 1)
    #expect(result.filter { $0.contains("further-diagnostics-suppressed limit=64") }.count == 1)
    for _ in 0..<10_000 { warnings.report("🙂") }
    warnings.waitForPendingReports()
    #expect(lines.withLock { $0.count } == result.count)
  }

  @Test func boundedModeLimitsLongGraphemeMetadata() {
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings { line in lines.withLock { $0.append(line) } }
    warnings.report(Character("x" + String(repeating: "\u{0301}", count: 10_000)))
    warnings.report(Character("x" + String(repeating: "\u{0301}", count: 20_000)))
    warnings.waitForPendingReports()
    let result = lines.withLock { $0 }
    #expect(result.count == 1)
    #expect(result.first?.contains("truncated=true") == true)
    #expect(result.first?.components(separatedBy: "U+").count == MissingGlyphWarnings.scalarLimit + 1)
    #expect((result.first?.utf8.count ?? 0) < 256)
  }

  @Test func boundedSignaturesDistinguishExactAndTruncatedPrefixes() {
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings { line in lines.withLock { $0.append(line) } }
    let prefix = "x" + String(repeating: "\u{0301}", count: 15)
    warnings.report(Character(prefix))
    warnings.report(Character(prefix + "\u{0301}"))
    warnings.report(Character(prefix + "\u{0300}"))
    warnings.waitForPendingReports()
    let result = lines.withLock { $0 }
    #expect(result.count == 2)
    #expect(result.filter { $0.contains("truncated=true") }.count == 1)
  }

  @Test func verboseModeDoesNotTruncateGraphemes() {
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings(policy: .perOccurrence) { line in lines.withLock { $0.append(line) } }
    warnings.report(Character("x" + String(repeating: "\u{0301}", count: 31)))
    warnings.waitForPendingReports()
    let result = lines.withLock { $0 }
    #expect(result.count == 1)
    #expect(result.first?.contains("truncated") == false)
    #expect(result.first?.components(separatedBy: "U+").count == 33)
  }

  @Test func disabledModeProducesNoOutput() {
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings(policy: .disabled) { line in lines.withLock { $0.append(line) } }
    for _ in 0..<100 { warnings.report("🙂") }
    warnings.waitForPendingReports()
    #expect(lines.withLock { $0.isEmpty })
  }

  @Test func configurationDefaultsToBounded() {
    #expect(MissingGlyphWarnings.policy(for: nil) == .bounded)
    #expect(MissingGlyphWarnings.policy(for: "unknown") == .bounded)
    #expect(MissingGlyphWarnings.policy(for: "off") == .disabled)
    #expect(MissingGlyphWarnings.policy(for: "verbose") == .perOccurrence)
  }

  @Test func blockedSinkDoesNotBlockGlyphLookup() {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let calls = Mutex(0)
    let warnings = MissingGlyphWarnings { _ in
      let first = calls.withLock { count in
        count += 1
        return count == 1
      }
      if first {
        entered.signal()
        _ = release.wait(timeout: .now() + 10)
      }
    }
    let atlas = HighResolutionFontAtlas(missingGlyphWarnings: warnings)
    _ = atlas.glyphUV("🙂")
    #expect(entered.wait(timeout: .now() + 2) == .success)
    DispatchQueue.global().async {
      for scalar in 0xF0000..<0xF1000 {
        _ = atlas.glyphUV(Character(String(UnicodeScalar(scalar)!)))
      }
      finished.signal()
    }
    let completed = finished.wait(timeout: .now() + 2)
    release.signal()
    warnings.waitForPendingReports()
    #expect(completed == .success)
    #expect(calls.withLock { $0 } == MissingGlyphWarnings.signatureLimit + 1)
  }

  @Test func diagnosticPolicyDoesNotChangeFallbackCoordinates() {
    let quiet = HighResolutionFontAtlas(missingGlyphWarnings: MissingGlyphWarnings(policy: .disabled))
    let lines = Mutex([String]())
    let warnings = MissingGlyphWarnings { line in lines.withLock { $0.append(line) } }
    let reported = HighResolutionFontAtlas(missingGlyphWarnings: warnings)
    #expect(quiet.glyphUV("🙂") == quiet.glyphUV("�"))
    #expect(reported.glyphUV("🙂") == quiet.glyphUV("🙂"))
    #expect(reported.glyphUV("A") == quiet.glyphUV("A"))
    warnings.waitForPendingReports()
    #expect(lines.withLock { $0.count } == 1)
  }
}
