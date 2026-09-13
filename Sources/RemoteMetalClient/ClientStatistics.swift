import Foundation

struct ClientStatistics {
  var startedAt = ProcessInfo.processInfo.systemUptime
  var frames = 0
  var bytes = 0
  var commands = 0
  var decodeTime: TimeInterval = 0
  var renderTime: TimeInterval = 0
  var draws = 0
  var drawCalls = 0
  var instances = 0
  var gpuTime: TimeInterval = 0
  var gpuFrames = 0
  var requestTime: TimeInterval = 0
  var replies = 0

  mutating func reportIfNeeded() {
    let now = ProcessInfo.processInfo.systemUptime
    let elapsed = now - startedAt
    guard elapsed >= 1 else { return }
    let frameCount = max(1, frames)
    func decimal(_ value: Double, places: Int = 2) -> String {
      value.formatted(
        .number.locale(Locale(identifier: "en_US_POSIX"))
          .grouping(.never).precision(.fractionLength(places)))
    }
    let message = [
      "client \(decimal(Double(frames) / elapsed, places: 1)) received fps",
      "\(decimal(Double(draws) / elapsed, places: 1)) rendered fps",
      "\(decimal(Double(bytes) * 8 / elapsed / 1_000_000)) Mbit/s",
      "\(decimal(Double(commands) / Double(frameCount), places: 0)) commands/frame",
      "decode \(decimal(decodeTime * 1_000 / Double(frameCount))) ms",
      "CPU encode \(decimal(renderTime * 1_000 / Double(max(1, draws)))) ms",
      "GPU \(decimal(gpuTime * 1_000 / Double(max(1, gpuFrames)))) ms",
      "request \(decimal(requestTime * 1_000 / Double(max(1, replies)))) ms",
      "\(decimal(Double(drawCalls) / Double(max(1, draws)), places: 0)) draws/frame",
      "\(decimal(Double(instances) / Double(max(1, draws)), places: 0)) instances/frame",
    ].joined(separator: " | ")
    // FileHandle avoids C FILE* access and writes without a stdio flush boundary.
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
    self = Self()
    startedAt = now
  }
}
