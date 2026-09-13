import Foundation
import Testing

@testable import CompareBenchmarks

struct ComparisonTests {
  @Test func regressionAndMetadataChecks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    func write(_ name: String, p95: Double = 2, hardware: String = "same", frames: Int = 300, seconds: Double = 20)
      throws -> BenchmarkRuns
    {
      let directory = root.appendingPathComponent(name)
      for trial in 0..<3 {
        let path = directory.appendingPathComponent("trial-\(trial)")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        for metadata in BenchmarkRuns.metadataNames {
          try Data((metadata == "hardware.txt" ? hardware : "same").utf8)
            .write(to: path.appendingPathComponent(metadata))
        }
        var report: [String: Any] = Dictionary(uniqueKeysWithValues: BenchmarkRuns.configKeys.map { ($0, 1) })
        report["frames"] = frames + trial
        report["minimumSeconds"] = seconds
        report["profilingEnabled"] = false
        report["timings"] = ["cull": ["p50MS": 1.0, "p95MS": p95]]
        try JSONSerialization.data(withJSONObject: report).write(to: path.appendingPathComponent("text-cull.json"))
      }
      return try BenchmarkRuns(directory: directory)
    }
    let baseline = try write("baseline")
    let identical = try write("candidate")
    #expect(try !baseline.compare(to: identical, threshold: 15, emit: { _ in }))
    let moreSamples = try write("longer", frames: 500)
    #expect(try !baseline.compare(to: moreSamples, threshold: 15, emit: { _ in }))
    let differentDuration = try write("duration", seconds: 30)
    #expect(throws: ComparisonError.self) {
      try baseline.compare(to: differentDuration, threshold: 15, emit: { _ in })
    }
    let slower = try write("candidate", p95: 3)
    #expect(try baseline.compare(to: slower, threshold: 15, emit: { _ in }))
    let differentHardware = try write("candidate", hardware: "different")
    #expect(throws: ComparisonError.self) {
      try baseline.compare(to: differentHardware, threshold: 15, emit: { _ in })
    }
    #expect(throws: ComparisonError.self) {
      try baseline.compare(to: identical, threshold: .nan, emit: { _ in })
    }
    #expect(throws: ComparisonError.self) { try write("invalid", p95: 0) }
  }
}
