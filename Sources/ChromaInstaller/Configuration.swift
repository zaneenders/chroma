import Foundation

struct InstallError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

struct Configuration: Codable, Equatable {
  var version = 1
  var packagePath = "."
  var product: String
  var displayName: String
  var identifier: String
  var configuration = "release"
  var linuxPrefix = "~/.local"
  var macOSDestination = "~/Applications/Chroma.app"
  var signingIdentity = "-"

  func validate() throws {
    guard version == 1 else { throw InstallError("Unsupported config version: \(version)") }
    let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
    guard !product.isEmpty, product != ".", product != "..",
      product.unicodeScalars.allSatisfy(safe.contains),
      identifier.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }),
      identifier.contains("."), identifier.unicodeScalars.allSatisfy(safe.contains),
      !displayName.isEmpty, !displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      ["release", "debug"].contains(configuration), !signingIdentity.isEmpty
    else { throw InstallError("Invalid product, app name, identifier, configuration, or signing identity.") }
  }

  static func load(_ url: URL) throws -> Self {
    let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    try result.validate()
    return result
  }

  func save(_ url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}

func resolve(_ path: String, relativeTo base: URL) -> URL {
  let directory = URL(fileURLWithPath: base.path, isDirectory: true)
  return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, relativeTo: directory).standardizedFileURL
}

struct Options {
  var config: String?
  var yes = false
  var help = false
  var overrides: [String: String] = [:]

  init(_ arguments: [String]) throws {
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--yes": yes = true
      case "--help", "-h": help = true
      case "--prefix", "--destination", "--configuration", "--signing-identity":
        index += 1
        guard index < arguments.count, !arguments[index].hasPrefix("--"), overrides[argument] == nil else {
          throw InstallError("Provide \(argument) once with a value.")
        }
        overrides[argument] = arguments[index]
      default:
        guard !argument.hasPrefix("-"), config == nil else { throw InstallError("Unexpected argument: \(argument)") }
        config = argument
      }
      index += 1
    }
  }
}
