import ChromaFont
import Foundation

// Deliberately uses only APIs available on the baseline so the fixture can be copied unchanged.
let atlas = HighResolutionFontAtlas()
let distinct = CommandLine.arguments.contains("--distinct")
let characters: [Character] =
  distinct
  ? (0xF0000..<0xF0100).map { Character(String(UnicodeScalar($0)!)) }
  : ["👋"]
let iterations = 200_000
var checksum: Float = 0
let start = ContinuousClock.now
for index in 0..<iterations {
  let uv = atlas.glyphUV(characters[index % characters.count])
  checksum += uv.0 + uv.1 + uv.2 + uv.3
}
let elapsed = start.duration(to: .now)
let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
print(
  "scenario=\(distinct ? "distinct-256" : "repeated") lookups=\(iterations) seconds=\(seconds) checksum=\(checksum)")
// Diagnostic delivery is best effort and deliberately excluded from timed lookup latency.
// Give the bounded default time to write its at-most-65 records for log-volume inspection.
Thread.sleep(forTimeInterval: 0.2)
