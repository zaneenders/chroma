import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct TraceOptions {
  let path: String
  var refreshHz = 60.0
  var start = 0.0
  var end = Double.infinity

  init(_ arguments: [String]) throws {
    guard let path = arguments.first, !path.hasPrefix("--") else { throw TraceError("Expected a trace path") }
    self.path = path
    var index = 1
    while index < arguments.count {
      let flag = arguments[index]
      guard index + 1 < arguments.count, let value = Double(arguments[index + 1]), value.isFinite else {
        throw TraceError("Expected a finite number after \(flag)")
      }
      switch flag {
      case "--refresh-hz": refreshHz = value
      case "--start": start = value
      case "--end": end = value
      default: throw TraceError("Unknown option: \(flag)")
      }
      index += 2
    }
  }
}

struct DependencyNode: Decodable {
  var identity: String?
  var path: String?
  var dependencies: [DependencyNode]?

  func containsChroma(at source: URL) -> Bool {
    if identity == "chroma", let path,
      URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path == source.path
    {
      return true
    }
    return dependencies?.contains { $0.containsChroma(at: source) } ?? false
  }

  static func verify(data: Data, source: String) throws {
    let graph = try JSONDecoder().decode(Self.self, from: data)
    let source = URL(fileURLWithPath: source).standardizedFileURL.resolvingSymlinksInPath()
    guard graph.containsChroma(at: source) else {
      throw TraceError(
        "Chroma dependency does not use the requested source checkout; configure a local override first.")
    }
  }
}

@main
struct NativeTraceCommand {
  static let usage = """
    Usage: NativeTrace TRACE.json [--refresh-hz HZ] [--start SECONDS] [--end SECONDS]
           NativeTrace --verify-dependency DEPENDENCY_GRAPH.json CHROMA_SOURCE
    Summarize bounded native traces in milliseconds; ranges are relative to capture start.
    """

  static func main() {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] || arguments == ["-h"] {
      print(usage)
      return
    }
    do {
      if arguments.first == "--verify-dependency" {
        guard arguments.count == 3 else { throw TraceError("Expected dependency graph and source path") }
        try DependencyNode.verify(data: Data(contentsOf: URL(fileURLWithPath: arguments[1])), source: arguments[2])
      } else {
        let options = try TraceOptions(arguments)
        let trace = try NativeTrace(data: Data(contentsOf: URL(fileURLWithPath: options.path)))
        let summary = try trace.summarize(refreshHz: options.refreshHz, start: options.start, end: options.end)
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try FileHandle.standardOutput.write(contentsOf: data + Data("\n".utf8))
      }
    } catch {
      try? FileHandle.standardError.write(contentsOf: Data("NativeTrace: \(error)\n\(usage)\n".utf8))
      exit(1)
    }
  }
}
