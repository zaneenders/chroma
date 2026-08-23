import Foundation

@main
struct MetalSourceGenerator {
  static func main() throws {
    guard CommandLine.arguments.count == 3 else {
      throw GeneratorError.usage
    }

    let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let source = try String(contentsOf: inputURL, encoding: .utf8)

    var hashes = "#"
    while source.contains("\"\"\"\(hashes)") || source.contains("\\\(hashes)(") {
      hashes += "#"
    }

    let generated = """
      // Generated from \(inputURL.lastPathComponent) by MetalSourcePlugin. Do not edit.
      let metalSource = \(hashes)\"\"\"
      \(source)\(source.hasSuffix("\n") ? "" : "\n")\"\"\"\(hashes)

      """

    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try generated.write(to: outputURL, atomically: true, encoding: .utf8)
  }
}

enum GeneratorError: Error, CustomStringConvertible {
  case usage

  var description: String {
    "usage: MetalSourceGenerator <input.metal> <output.swift>"
  }
}
