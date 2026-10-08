import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

@main
struct ChromaInstaller {
  static func main() {
    do {
      var arguments = Array(CommandLine.arguments.dropFirst())
      let profiling = arguments.last != "--without-profiling"
      if !profiling { arguments.removeLast() }
      guard arguments.count == 2 || arguments.count == 3 else {
        throw InstallError("Invoke swift package chroma-install [--without-profiling] from the app package.")
      }
      let package = URL(fileURLWithPath: arguments[0], isDirectory: true)
      let metadata = try AppMetadata(package: package, product: arguments[1])
      let installer = AppInstaller(metadata: metadata, profiling: profiling)
      try installer.preflight()
      if arguments.count == 3 {
        try installer.install(binary: URL(fileURLWithPath: arguments[2]))
        print("Installed \(metadata.name) at \(installer.destination.path)")
      }
    } catch {
      try? FileHandle.standardError.write(contentsOf: Data("chroma-install: \(error)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }
}

@discardableResult
func runCommand(_ executable: String, _ arguments: [String], capture: Bool = false) throws -> String {
  let process = Process()
  let pipe = capture ? Pipe() : nil
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  if let pipe { process.standardOutput = pipe } else { process.standardOutput = FileHandle.standardOutput }
  process.standardError = FileHandle.standardError
  try process.run()
  // Drain while the process runs; waiting before reading can deadlock on a full pipe.
  let output = pipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
  process.waitUntilExit()
  guard process.terminationReason == .exit, process.terminationStatus == 0 else {
    throw InstallError("\(executable) exited with status \(process.terminationStatus).")
  }
  return String(decoding: output, as: UTF8.self)
}

func developmentIdentity(in output: String) throws -> String {
  for line in output.split(separator: "\n") {
    let fields = line.split(separator: "\"")
    if fields.count >= 2, fields[1].hasPrefix("Apple Development:") { return String(fields[1]) }
  }
  throw InstallError(
    """
    No accessible Apple Development signing identity found.
    On macOS, rerun swift package with --disable-sandbox so the installer can access the Keychain.
    If no identity is found outside the sandbox, create one in Xcode (Settings > Accounts > Manage Certificates).
    """)
}
