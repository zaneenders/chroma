import Foundation
import Testing

@testable import CompareBenchmarks

struct ComparisonTests {
  @Test func openGLReportsRequireMatchingDriverMetadata() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    func write(_ name: String, driver: [String: String]?) throws -> BenchmarkRuns {
      let directory = root.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for metadata in BenchmarkRuns.metadataNames {
        try Data("same".utf8).write(to: directory.appendingPathComponent(metadata))
      }
      var report: [String: Any] = Dictionary(uniqueKeysWithValues: BenchmarkRuns.configKeys.map { ($0, 1) })
      report["stage"] = "opengl"
      if let driver { report["rendererInfo"] = driver }
      report["timings"] = ["openGLEncode": ["p50MS": 1.0, "p95MS": 2.0]]
      try JSONSerialization.data(withJSONObject: report)
        .write(to: directory.appendingPathComponent("scrolling-opengl.json"))
      return try BenchmarkRuns(directory: directory)
    }
    let driver = ["vendor": "Mesa", "renderer": "GPU", "version": "ES3"]
    let baseline = try write("baseline", driver: driver)
    let identical = try write("identical", driver: driver)
    #expect(try !baseline.compare(to: identical, threshold: 15, emit: { _ in }))
    for key in driver.keys {
      var changed = driver
      changed[key] = "different"
      let candidate = try write(key, driver: changed)
      #expect(throws: ComparisonError.self) {
        try baseline.compare(to: candidate, threshold: 15, emit: { _ in })
      }
    }
    #expect(throws: ComparisonError.self) { try write("missing", driver: nil) }
    #expect(throws: ComparisonError.self) { try write("incomplete", driver: ["renderer": "GPU"]) }
  }

  @Test func stressReportsCompareAndRejectWorkloadChanges() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    func write(_ name: String, p95: Double = 2, changedKey: String? = nil) throws -> BenchmarkRuns {
      let directory = root.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for metadata in BenchmarkRuns.metadataNames {
        try Data("same".utf8).write(to: directory.appendingPathComponent(metadata))
      }
      var report: [String: Any] = [
        "benchmarkKind": "stress", "schemaVersion": 1, "fixtureVersion": 1,
        "viewport": ["width": 1440, "height": 900],
        "configuration": ["rows": 100000, "panes": 3, "depth": 8, "events": 12],
        "samples": 30, "warmup": 5, "phaseSamples": ["input-burst": 30],
        "timings": ["input-burst": ["p50MS": 1.0, "p95MS": p95]],
      ]
      if let changedKey { report[changedKey] = 999 }
      try JSONSerialization.data(withJSONObject: report)
        .write(to: directory.appendingPathComponent("stress-headless.json"))
      return try BenchmarkRuns(directory: directory)
    }
    let baseline = try write("baseline")
    let identical = try write("identical")
    #expect(try !baseline.compare(to: identical, threshold: 15, emit: { _ in }))
    let slower = try write("slower", p95: 3)
    #expect(try baseline.compare(to: slower, threshold: 15, emit: { _ in }))
    for key in BenchmarkRuns.stressConfigKeys where key != "benchmarkKind" {
      let changed = try write(key, changedKey: key)
      #expect(throws: ComparisonError.self) {
        try baseline.compare(to: changed, threshold: 15, emit: { _ in })
      }
    }
    #expect(throws: ComparisonError.self) { try write("invalid", p95: 0) }
  }

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
