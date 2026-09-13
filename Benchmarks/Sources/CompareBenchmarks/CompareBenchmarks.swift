import Foundation

struct ComparisonError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

struct BenchmarkRuns {
  static let metadataNames = ["toolchain.txt", "hardware.txt", "dependencies.json"]
  static let configKeys = [
    "schemaVersion", "fixtureVersion", "os", "processors",
    "scene", "stage", "count", "warmup", "minimumFrames", "minimumSeconds", "sequenceFrames",
    "commandCountMin", "commandCountMax",
  ]
  var metadata: [Data] = []
  var configs: [String: Data] = [:]
  var results: [String: [[String: Double]]] = [:]

  init(directory: URL) throws {
    let files = FileManager.default
    let trials = try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.hasPrefix("trial-") }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var expectedNames: Set<String>?
    for trial in trials.isEmpty ? [directory] : trials {
      let currentMetadata = try Self.metadataNames.map { try Data(contentsOf: trial.appendingPathComponent($0)) }
      guard metadata.isEmpty || metadata == currentMetadata else {
        throw ComparisonError("Metadata differs between trials")
      }
      metadata = currentMetadata
      let reports = try files.contentsOfDirectory(at: trial, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" && $0.lastPathComponent.contains("-") }
      let names = Set(reports.map(\.lastPathComponent))
      guard !names.isEmpty, expectedNames == nil || expectedNames == names else {
        throw ComparisonError("Empty or inconsistent trial workloads")
      }
      expectedNames = names
      for path in reports {
        let name = path.lastPathComponent
        guard let report = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any],
          let profiling = report["profilingEnabled"] as? Bool, !profiling,
          let timings = report["timings"] as? [String: [String: Double]], !timings.isEmpty
        else { throw ComparisonError("Invalid or profiled report: \(name)") }
        var config: [String: Any] = [:]
        for key in Self.configKeys {
          guard let value = report[key] else { throw ComparisonError("Missing \(key): \(name)") }
          config[key] = value
        }
        let encoded = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        guard configs[name] == nil || configs[name] == encoded else {
          throw ComparisonError("Incompatible trial configuration: \(name)")
        }
        configs[name] = encoded
        var metrics: [String: Double] = [:]
        for (phase, timing) in timings {
          for percentile in ["p50MS", "p95MS"] {
            guard let value = timing[percentile], value.isFinite, value > 0 else {
              throw ComparisonError("Invalid timing: \(name)/\(phase)/\(percentile)")
            }
            metrics["\(phase)/\(percentile)"] = value
          }
        }
        results[name, default: []].append(metrics)
      }
    }
  }

  func compare(to candidate: Self, threshold: Double, emit: (String) -> Void) throws -> Bool {
    guard threshold.isFinite, threshold >= 0 else {
      throw ComparisonError("Threshold must be finite and nonnegative")
    }
    guard configs == candidate.configs, metadata == candidate.metadata else {
      throw ComparisonError("Incompatible workloads, configuration, toolchain, dependencies or hardware")
    }
    var regressed = false
    for name in results.keys.sorted() {
      let old = results[name]!
      let new = candidate.results[name]!
      let keys = Set(old[0].keys)
      guard (old + new).allSatisfy({ Set($0.keys) == keys }) else {
        throw ComparisonError("Incompatible timing phases: \(name)")
      }
      for metric in keys.sorted() {
        let before = old.map { $0[metric]! }.sorted()
        let after = new.map { $0[metric]! }.sorted()
        func median(_ values: [Double]) -> Double {
          (values[(values.count - 1) / 2] + values[values.count / 2]) / 2
        }
        let a = median(before)
        let b = median(after)
        let change = (b / a - 1) * 100
        let spreadA = (before.last! - before.first!) / a * 100
        let spreadB = (after.last! - after.first!) / b * 100
        regressed = regressed || change > threshold
        emit(
          String(
            format: "%@/%@: %.4f -> %.4f ms (%+.1f%%) spread %.1f%%/%.1f%% trials %d/%d%@",
            name, metric, a, b, change, spreadA, spreadB, before.count, after.count,
            change > threshold ? " REGRESSION" : ""))
      }
    }
    return regressed
  }
}

@main
enum CompareBenchmarks {
  static func main() {
    do {
      let args = Array(CommandLine.arguments.dropFirst())
      guard args.count == 2 || (args.count == 4 && args[2] == "--max-regression-percent") else {
        throw ComparisonError("usage: CompareBenchmarks BASELINE CANDIDATE [--max-regression-percent NUMBER]")
      }
      guard let threshold = Double(args.count == 4 ? args[3] : "15") else {
        throw ComparisonError("Invalid threshold")
      }
      let baseline = try BenchmarkRuns(directory: URL(fileURLWithPath: args[0]))
      let candidate = try BenchmarkRuns(directory: URL(fileURLWithPath: args[1]))
      print("Medians across trials; spread is (max-min)/median, not a confidence interval.")
      let regressed = try baseline.compare(to: candidate, threshold: threshold) { print($0) }
      if regressed { exit(1) }
    } catch {
      FileHandle.standardError.write(Data("\(error)\n".utf8))
      exit(1)
    }
  }
}
