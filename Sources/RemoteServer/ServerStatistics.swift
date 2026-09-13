import Foundation
import Logging

struct ServerStatistics {
  private var logger = Logger(label: "chroma.remote.server")
  var startedAt = ProcessInfo.processInfo.systemUptime
  var frames = 0
  var bytes = 0
  var imageBytes = 0
  var commands = 0
  var drawTime: TimeInterval = 0
  var encodeTime: TimeInterval = 0

  private static func decimal(_ value: Double, places: Int) -> String {
    value.formatted(
      .number.locale(Locale(identifier: "en_US_POSIX"))
        .grouping(.never).precision(.fractionLength(places)))
  }

  mutating func record(
    byteCount: Int, commandCount: Int, drawDuration: TimeInterval, encodeDuration: TimeInterval
  ) {
    frames += 1
    bytes += byteCount
    commands += commandCount
    drawTime += drawDuration
    encodeTime += encodeDuration
    let now = ProcessInfo.processInfo.systemUptime
    let elapsed = now - startedAt
    guard elapsed >= 1 else { return }
    let frameCount = max(1, frames)
    let megabitsPerSecond = Double(bytes) * 8 / elapsed / 1_000_000
    logger.info(
      "Remote rendering statistics",
      metadata: [
        "fps": "\(Self.decimal(Double(frames) / elapsed, places: 1))",
        "megabits_per_second": "\(Self.decimal(megabitsPerSecond, places: 2))",
        "commands_per_frame": "\(Self.decimal(Double(commands) / Double(frameCount), places: 0))",
        "image_mbit_s": "\(Self.decimal(Double(imageBytes) * 8 / elapsed / 1_000_000, places: 2))",
        "command_mbit_s":
          "\(Self.decimal(Double(bytes - imageBytes) * 8 / elapsed / 1_000_000, places: 2))",
        "draw_ms": "\(Self.decimal(drawTime * 1_000 / Double(frameCount), places: 2))",
        "encode_ms": "\(Self.decimal(encodeTime * 1_000 / Double(frameCount), places: 2))",
      ])
    self = Self()
    startedAt = now
  }
}
