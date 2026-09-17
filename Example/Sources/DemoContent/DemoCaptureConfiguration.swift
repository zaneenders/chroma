import Foundation

public struct DemoCaptureConfiguration: Sendable {
  public let directory: URL

  public init(directory: URL) throws {
    guard directory.isFileURL else { throw ConfigurationError.invalidDirectory }
    let directory = directory.standardizedFileURL.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { throw ConfigurationError.invalidDirectory }
    let probe = directory.appendingPathComponent(".chroma-write-probe-\(UUID().uuidString)")
    guard
      FileManager.default.createFile(
        atPath: probe.path, contents: Data(),
        attributes: [.posixPermissions: 0o600])
    else { throw ConfigurationError.notWritable }
    try FileManager.default.removeItem(at: probe)
    self.directory = directory
  }

  public static func nativeDefault() throws -> Self {
    let directory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    #if os(macOS)
    let installed = Bundle.main.bundleURL.pathExtension == "app"
    #else
    let executableDirectory = Bundle.main.bundleURL
    let installed = FileManager.default.fileExists(
      atPath: executableDirectory.appendingPathComponent(".chroma-install").path)
    #endif
    if installed || !FileManager.default.fileExists(atPath: directory.path) {
      let dataDirectory = try FileManager.default.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
      )
      .appendingPathComponent("ChromaDemo/Captures", isDirectory: true)
      try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
      return try Self(directory: dataDirectory)
    }
    return try Self(directory: directory)
  }

  public static func parse(arguments: inout [String]) throws -> Self? {
    var path: String?
    var remaining: [String] = []
    var index = 0
    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--capture-directory" {
        guard path == nil, index + 1 < arguments.count,
          !arguments[index + 1].hasPrefix("--"),
          !arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
          throw ConfigurationError.missingOrDuplicateDirectory
        }
        path = arguments[index + 1]
        index += 2
      } else {
        if argument.hasPrefix("--capture") { throw ConfigurationError.missingOrDuplicateDirectory }
        remaining.append(argument)
        index += 1
      }
    }
    arguments = remaining
    guard let path else { return nil }
    let expanded = (path as NSString).expandingTildeInPath
    return try Self(directory: URL(fileURLWithPath: expanded, isDirectory: true))
  }

  public enum ConfigurationError: Error, CustomStringConvertible {
    case invalidDirectory, notWritable, missingOrDuplicateDirectory
    public var description: String {
      switch self {
      case .invalidDirectory: "Capture directory must be an existing local directory. Create it first."
      case .notWritable: "Capture directory is not writable."
      case .missingOrDuplicateDirectory: "Provide --capture-directory PATH exactly once to enable capture."
      }
    }
  }
}
