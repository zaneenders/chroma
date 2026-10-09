import Foundation
import Testing

@testable import NativeTrace

struct NativeTraceCommandTests {
  @Test func optionsUseCaptureRelativeRangesAndDefaults() throws {
    let defaults = try TraceOptions(["trace.json"])
    #expect(defaults.path == "trace.json")
    #expect(defaults.refreshHz == 60 && defaults.start == 0 && defaults.end == .infinity)
    let options = try TraceOptions(["trace.json", "--end", "13", "--start", "3", "--refresh-hz", "120"])
    #expect(options.refreshHz == 120 && options.start == 3 && options.end == 13)
    for arguments in [
      [], ["--start", "1"], ["trace.json", "--end"], ["trace.json", "--unknown", "1"],
      ["trace.json", "--start", "nan"], ["trace.json", "--end", "inf"], ["trace.json", "extra"],
    ] {
      #expect(throws: TraceError.self) { try TraceOptions(arguments) }
    }
  }

  @Test func dependencyVerificationFindsOnlyTheRequestedChromaCheckout() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    let link = root.appendingPathComponent("link")
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
    func graph(identity: String = "chroma", path: String?) throws -> Data {
      var node: [String: Any] = ["identity": identity]
      if let path { node["path"] = path }
      return try JSONSerialization.data(withJSONObject: [
        "identity": "app", "dependencies": [["identity": "nested", "dependencies": [node]]],
      ])
    }
    let data = try graph(path: link.path)
    try DependencyNode.verify(data: data, source: source.path)
    try DependencyNode.verify(data: data, source: source.appendingPathComponent(".").path)
    #expect(throws: TraceError.self) {
      try DependencyNode.verify(data: data, source: root.appendingPathComponent("wrong").path)
    }
    for data in [try graph(identity: "other", path: source.path), try graph(path: nil), Data("{}".utf8)] {
      #expect(throws: TraceError.self) { try DependencyNode.verify(data: data, source: source.path) }
    }
    #expect(throws: (any Error).self) { try DependencyNode.verify(data: Data("not json".utf8), source: source.path) }
  }
}
