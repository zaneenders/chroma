import Chroma
import Foundation

/// An executable App with no native window or graphics dependency.
public protocol HeadlessApp: App {}

extension HeadlessApp {
  @MainActor public static func main() async {
    await HeadlessSession.runProcess(Self())
  }
}

extension HeadlessSession {
  /// Runs a headless executable and reports startup/I/O failures on stderr with exit status 1.
  @MainActor public static func runProcess<A: App>(_ app: @autoclosure () -> A) async {
    do { try await run(app()) } catch { failProcess(error) }
  }

  /// Starts a JSONL process. --viewport WIDTHxHEIGHT is required.
  @MainActor public static func run<A: App>(
    _ app: @autoclosure () -> A, arguments: [String] = Array(CommandLine.arguments.dropFirst())
  ) async throws {
    let channels = try StandardIOChannels()
    defer { withExtendedLifetime(channels) {} }
    var onlyChanges = true
    var viewport: Size?
    var index = 0
    while index < arguments.count {
      switch arguments[index] {
      case "--headless": break
      case "--all-changes": onlyChanges = false
      case "--viewport":
        index += 1
        guard index < arguments.count else { throw HeadlessArgumentError.usage }
        let parts = arguments[index].split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let width = Float(parts[0]), let height = Float(parts[1]) else {
          throw HeadlessArgumentError.usage
        }
        viewport = Size(width: width, height: height)
      default: throw HeadlessArgumentError.usage
      }
      index += 1
    }
    guard let viewport else { throw HeadlessArgumentError.usage }
    let session = try HeadlessSession(app(), viewport: viewport)
    try await session.runStandardIO(output: channels.output, onlyChanges: onlyChanges)
  }
}

private enum HeadlessArgumentError: Error, CustomStringConvertible {
  case usage
  var description: String { "Usage: [--headless] [--all-changes] --viewport WIDTHxHEIGHT (dimensions 1...16384)" }
}
