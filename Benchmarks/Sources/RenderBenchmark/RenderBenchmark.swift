import Chroma
import Foundation
import RenderFixtures

enum BenchmarkError: Error { case failed(String) }
func now() -> Double { ProcessInfo.processInfo.systemUptime }

struct Distribution: Codable {
  let meanMS: Double
  let p50MS: Double
  let p95MS: Double
  init(_ samples: [Double]) {
    let sorted = samples.sorted()
    meanMS = samples.reduce(0, +) / Double(samples.count) * 1000
    p50MS = sorted[(sorted.count - 1) / 2] * 1000
    p95MS = sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)] * 1000
  }
}

struct Report: Codable {
  let schemaVersion: Int
  let fixtureVersion: Int
  let sequenceFrames: Int
  let commandCountMin: Int
  let commandCountMax: Int
  let os: String
  let processors: Int
  let scene: String
  let stage: String
  let count: Int
  let frames: Int
  let minimumFrames: Int
  let minimumSeconds: Double
  let warmup: Int
  let coldMS: [String: Double]
  let timings: [String: Distribution]
  let rendererInfo: [String: String]?
  let renderWork: [String: Int]?
}

@main
struct RenderBenchmark {
  @MainActor static func main() async throws {
    #if DEBUG
    throw BenchmarkError.failed("Use a release build: swift run -c release RenderBenchmark")
    #else
    var options: [String: String] = [:]
    var arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] {
      print(
        "RenderBenchmark [--scene \(RenderFixture.names.joined(separator: "|"))] [--stage cull|metal|opengl] [--count 2000] [--frames 300] [--warmup 30] [--seconds 0]"
      )
      return
    }
    let allowed = Set(["--scene", "--stage", "--count", "--frames", "--warmup", "--seconds"])
    while !arguments.isEmpty {
      let key = arguments.removeFirst()
      guard allowed.contains(key), !arguments.isEmpty, options[key] == nil else {
        throw BenchmarkError.failed("Invalid or duplicate option: \(key)")
      }
      options[key] = arguments.removeFirst()
    }
    let scene = options["--scene"] ?? "shapes"
    let stage = options["--stage"] ?? "cull"
    guard RenderFixture.names.contains(scene), ["cull", "metal", "opengl"].contains(stage),
      let count = Int(options["--count"] ?? "2000"), (1...100_000).contains(count),
      let frames = Int(options["--frames"] ?? "300"), (1...1_000_000).contains(frames),
      let warmup = Int(options["--warmup"] ?? "30"), (0...100_000).contains(warmup),
      let seconds = Double(options["--seconds"] ?? "0"), seconds.isFinite, (0...3600).contains(seconds)
    else { throw BenchmarkError.failed("Invalid benchmark configuration; see --help") }
    let fixture = try RenderFixture(name: scene, count: count)
    let sequence = fixture.sequence
    let viewport = fixture.viewport
    let rasterScale = Point(x: 1, y: 1)
    #if os(macOS)
    guard stage != "opengl" else { throw BenchmarkError.failed("OpenGL stages require Linux") }
    let metal = stage == "metal" ? try MetalReplay(viewport: viewport, rasterScale: rasterScale) : nil
    #elseif os(Linux)
    guard stage != "metal" else { throw BenchmarkError.failed("Metal stages require macOS") }
    let openGL = stage == "opengl" ? try OpenGLReplay(viewport: viewport) : nil
    #else
    guard stage == "cull" else { throw BenchmarkError.failed("Native stages require macOS or Linux") }
    #endif
    var samples: [String: [Double]] = [:]
    var cold: [String: Double] = [:]
    var iteration = 0
    var measured = 0
    var measurementStart = now()
    repeat {
      var durations: [String: Double] = [:]
      let sequenceIndex = iteration > warmup ? measured : iteration
      let source = sequence[sequenceIndex % sequence.count]
      let cullStart = now()
      let replay = source.culled(to: viewport)
      durations["cull"] = now() - cullStart
      guard replay.commands.count <= source.commands.count else {
        throw BenchmarkError.failed("Culling increased command count")
      }
      #if os(macOS)
      if let metal {
        let timing = try metal.render(replay, viewport: viewport)
        durations["metalEncode"] = timing.cpu
        durations["gpu"] = timing.gpu
      }
      #elseif os(Linux)
      if let openGL {
        let timing = try openGL.render(replay, viewport: viewport)
        durations["openGLEncode"] = timing.cpu
        durations["openGLCompletion"] = timing.completion
      }
      #endif
      if iteration == 0 {
        cold = durations.mapValues { $0 * 1000 }
      } else if iteration > warmup {
        for (name, value) in durations { samples[name, default: []].append(value) }
        measured += 1
      }
      iteration += 1
      if iteration == warmup + 1 { measurementStart = now() }
      #if os(Linux)
      // EGL contexts are thread-local, even when Swift actor isolation is unchanged.
      if openGL == nil { await Task.yield() }
      #else
      await Task.yield()
      #endif
    } while measured < frames || now() - measurementStart < seconds
    #if os(Linux)
    let rendererInfo = openGL?.info
    let renderWork = openGL?.work
    #else
    let rendererInfo: [String: String]? = nil
    let renderWork: [String: Int]? = nil
    #endif
    let report = Report(
      schemaVersion: 6, fixtureVersion: RenderFixture.version,
      sequenceFrames: sequence.count,
      commandCountMin: sequence.map { $0.commands.count }.min()!,
      commandCountMax: sequence.map { $0.commands.count }.max()!,
      os: ProcessInfo.processInfo.operatingSystemVersionString,
      processors: ProcessInfo.processInfo.activeProcessorCount, scene: scene, stage: stage,
      count: count, frames: measured, minimumFrames: frames, minimumSeconds: seconds, warmup: warmup,
      coldMS: cold,
      timings: samples.mapValues(Distribution.init), rendererInfo: rendererInfo, renderWork: renderWork)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
    #endif
  }
}
