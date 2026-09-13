import Chroma
import Foundation
import Logging
import ProfileRecorderServer
import RemoteProtocol
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
  let protocolVersion: UInt16
  let os: String
  let processors: Int
  let scene: String
  let stage: String
  let count: Int
  let frames: Int
  let minimumFrames: Int
  let minimumSeconds: Double
  let warmup: Int
  let profilingEnabled: Bool
  let coldWireBytes: Int
  let steadyWireBytes: Int
  let coldMS: [String: Double]
  let timings: [String: Distribution]
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
        "RenderBenchmark [--scene \(RenderFixture.names.joined(separator: "|"))] [--capture PATH] [--stage wire|metal|pipeline] [--count 2000] [--frames 300] [--warmup 30] [--seconds 0]"
      )
      return
    }
    let allowed = Set(["--scene", "--stage", "--count", "--frames", "--warmup", "--seconds", "--capture"])
    while !arguments.isEmpty {
      let key = arguments.removeFirst()
      guard allowed.contains(key), !arguments.isEmpty, options[key] == nil else {
        throw BenchmarkError.failed("Invalid or duplicate option: \(key)")
      }
      options[key] = arguments.removeFirst()
    }
    var scene = options["--scene"] ?? "shapes"
    let stage = options["--stage"] ?? "wire"
    guard RenderFixture.names.contains(scene), ["wire", "metal", "pipeline"].contains(stage),
      let count = Int(options["--count"] ?? "2000"), (1...100_000).contains(count),
      let frames = Int(options["--frames"] ?? "300"), (1...1_000_000).contains(frames),
      let warmup = Int(options["--warmup"] ?? "30"), (0...100_000).contains(warmup),
      let seconds = Double(options["--seconds"] ?? "0"), seconds.isFinite, (0...3600).contains(seconds)
    else { throw BenchmarkError.failed("Invalid benchmark configuration; see --help") }
    let environment = ProcessInfo.processInfo.environment
    let profiling =
      environment["PROFILE_RECORDER_SERVER_URL_PATTERN"] != nil
      || environment["PROFILE_RECORDER_SERVER_URL"] != nil
    let profiler = Task {
      if profiling {
        let configuration = try await ProfileRecorderServerConfiguration.parseFromEnvironment()
        await ProfileRecorderServer(configuration: configuration)
          .runIgnoringFailures(logger: Logger(label: "chroma.benchmark.profiler"))
      }
    }
    defer { profiler.cancel() }
    let sequence: [DrawList]
    let viewport: Size
    let rasterScale: Point
    if let path = options["--capture"] {
      guard options["--scene"] == nil, options["--count"] == nil else {
        throw BenchmarkError.failed("--capture cannot be combined with --scene or --count")
      }
      let url = URL(fileURLWithPath: path)
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard let size = attributes[.size] as? NSNumber, size.intValue <= 65 * 1024 * 1024 else {
        throw BenchmarkError.failed("Capture exceeds file size limit")
      }
      let data = try Data(contentsOf: url)
      let frame = try SceneCapture.decode(data)
      sequence = [frame.drawList]
      viewport = frame.viewport
      rasterScale = frame.rasterScale ?? Point(x: 1, y: 1)
      let fingerprint = data.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
      scene = "capture-" + String(fingerprint, radix: 16)
    } else {
      let fixture = try RenderFixture(name: scene, count: count)
      sequence = fixture.sequence
      viewport = fixture.viewport
      rasterScale = Point(x: 1, y: 1)
    }
    #if os(macOS)
    let metal = stage == "wire" ? nil : try MetalReplay(viewport: viewport, rasterScale: rasterScale)
    #else
    guard stage == "wire" else { throw BenchmarkError.failed("Metal stages require macOS") }
    #endif
    var sender = RemoteImageCache()
    var receiver = RemoteImageCache()
    var samples: [String: [Double]] = [:]
    var cold: [String: Double] = [:]
    var coldBytes = 0
    var steadyBytes = 0
    var iteration = 0
    var measured = 0
    var measurementStart = now()
    repeat {
      var durations: [String: Double] = [:]
      let sequenceIndex = iteration > warmup ? measured : iteration
      let source = sequence[sequenceIndex % sequence.count]
      var replay = source
      var bytes = 0
      if stage != "metal" {
        let message = RemoteMessage.frame(
          id: UInt64(iteration), inputSequence: 0,
          viewport: viewport, commands: source.commands)
        let encodeStart = now()
        var wire = try RemoteWire.encode(message, images: &sender)
        durations["wireEncode"] = now() - encodeStart
        bytes = wire.readableBytes
        let decodeStart = now()
        let decoded = try RemoteWire.decode(from: &wire, images: &receiver)
        durations["wireDecode"] = now() - decodeStart
        guard case .frame(_, _, let decodedViewport, let commands) = decoded,
          decodedViewport == viewport, wire.readableBytes == 0
        else {
          throw BenchmarkError.failed("Invalid replay frame")
        }
        if iteration == 0, decoded != message { throw BenchmarkError.failed("Round-trip mismatch") }
        replay = DrawList(commands: commands)
      }
      #if os(macOS)
      if let metal {
        let timing = try metal.render(replay, viewport: viewport)
        durations["metalEncode"] = timing.cpu
        durations["gpu"] = timing.gpu
      }
      #endif
      if iteration == 0 {
        cold = durations.mapValues { $0 * 1000 }
        coldBytes = bytes
      } else if iteration > warmup {
        for (name, value) in durations { samples[name, default: []].append(value) }
        measured += 1
        steadyBytes = bytes
      }
      iteration += 1
      if iteration == warmup + 1 { measurementStart = now() }
      await Task.yield()
    } while measured < frames || now() - measurementStart < seconds
    let report = Report(
      schemaVersion: 3, fixtureVersion: RenderFixture.version,
      sequenceFrames: sequence.count,
      commandCountMin: sequence.map { $0.commands.count }.min()!,
      commandCountMax: sequence.map { $0.commands.count }.max()!,
      protocolVersion: RemoteWire.version, os: ProcessInfo.processInfo.operatingSystemVersionString,
      processors: ProcessInfo.processInfo.activeProcessorCount, scene: scene, stage: stage,
      count: count, frames: measured, minimumFrames: frames, minimumSeconds: seconds, warmup: warmup,
      profilingEnabled: profiling,
      coldWireBytes: coldBytes, steadyWireBytes: steadyBytes, coldMS: cold,
      timings: samples.mapValues(Distribution.init))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
    #endif
  }
}
