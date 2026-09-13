import Foundation

@main
struct ShaderSourceGenerator {
  static func main() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count >= 3, arguments.count % 2 == 1 else {
      throw GeneratorError.usage
    }
    let output = URL(fileURLWithPath: arguments[0])
    var generated = ""
    for index in stride(from: 1, to: arguments.count, by: 2) {
      let name = arguments[index]
      guard let first = name.utf8.first,
        first == 95 || (65...90).contains(first) || (97...122).contains(first),
        name.utf8.allSatisfy({ $0 == 95 || (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) }
        )
      else { throw GeneratorError.invalidName(name) }
      let source = try String(contentsOfFile: arguments[index + 1], encoding: .utf8)
      var hashes = "#"
      // Exclude every raw escape, not just interpolation.
      while source.contains("\"\"\"\(hashes)") || source.contains("\\\(hashes)") {
        hashes += "#"
      }
      generated += "let \(name) = \(hashes)\"\"\"\n\(source)\(source.hasSuffix("\n") ? "" : "\n")\"\"\"\(hashes)\n\n"
    }
    try FileManager.default.createDirectory(
      at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    try generated.write(to: output, atomically: true, encoding: .utf8)
  }
}

enum GeneratorError: Error {
  case usage
  case invalidName(String)
}
