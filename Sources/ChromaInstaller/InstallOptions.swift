import Foundation

struct InstallOptions {
  static let usage = "swift package chroma-install [--without-profiling] [--install-directory /absolute/path]"

  let positionalArguments: [String]
  let profiling: Bool
  let installDirectory: URL?

  init(arguments: [String]) throws {
    var positional: [String] = []
    var profiling = true
    var installDirectory: URL?
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      switch argument {
      case "--without-profiling":
        guard profiling else { throw InstallError("Duplicate --without-profiling option.") }
        profiling = false
      case "--install-directory":
        guard installDirectory == nil, index + 1 < arguments.count else {
          throw InstallError("Use \(Self.usage).")
        }
        index += 1
        let path = arguments[index]
        guard path.hasPrefix("/"), !path.contains("\0") else {
          throw InstallError("--install-directory requires an absolute directory path.")
        }
        installDirectory = URL(fileURLWithPath: path, isDirectory: true)
      default:
        guard !argument.hasPrefix("--") else { throw InstallError("Unknown installer option: \(argument)") }
        positional.append(argument)
      }
      index += 1
    }
    self.positionalArguments = positional
    self.profiling = profiling
    self.installDirectory = installDirectory
  }
}
