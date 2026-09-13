#if os(macOS)
import AppKit
import Darwin
import DemoBackend
import DemoContent
import Foundation
import RemoteMetalClient

@main
struct ManagedDemo {
  @MainActor
  static func main() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let backend = arguments.first == "--backend"
    if backend { arguments.removeFirst() }
    if arguments.contains("--help") || arguments.contains("-h") {
      print("usage: ChromaDemo [--capture-directory EXISTING_WRITABLE_DIRECTORY]")
      print("Launches an owned local backend and the remote Metal display client.")
      print("Save a capture with Ctrl+Shift+G; the default destination is Example/.")
      return
    }
    let capture =
      try DemoCaptureConfiguration.parse(arguments: &arguments)
      ?? DemoCaptureConfiguration.nativeDefault()
    guard arguments.isEmpty else {
      throw LaunchError.message("Unexpected arguments: \(arguments.joined(separator: " "))")
    }
    let demo = DemoApplication(shortcutModifier: .command, captureConfiguration: capture)
    if backend {
      let ready = FileHandle(fileDescriptor: dup(STDOUT_FILENO), closeOnDealloc: true)
      dup2(STDERR_FILENO, STDOUT_FILENO)
      let server = DemoBackend.makeServer(for: demo)
      try server.start(host: "127.0.0.1", port: 0)
      guard let port = server.boundPort else { throw LaunchError.message("No listening port") }
      try ready.write(contentsOf: Data("\(port)\n".utf8))
      try ready.close()
      DispatchQueue.global().async {
        while !FileHandle.standardInput.availableData.isEmpty {}
        DispatchQueue.main.async {
          try? server.shutdown()
          exit(0)
        }
      }
      server.run()
      return
    }

    let owner = OwnedBackend()
    defer { owner.stop() }
    let port = try owner.start(capture: capture)
    let client = try RemoteMetalClient(size: demo.windowSize, title: demo.title)
    try client.connect(host: "127.0.0.1", port: port, framesPerSecond: 60)
    let observer = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated { owner.stop() }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    owner.process.terminationHandler = { process in
      DispatchQueue.main.async {
        let alert = NSAlert()
        alert.messageText = "The local demo backend exited"
        alert.informativeText = "Backend exit status: \(process.terminationStatus). See the terminal for details."
        alert.runModal()
        NSApplication.shared.terminate(nil)
      }
    }
    guard owner.process.isRunning else { throw LaunchError.message("Backend exited during startup") }
    client.run()
  }
}

private enum LaunchError: Error, CustomStringConvertible {
  case message(String)
  var description: String {
    switch self {
    case .message(let text): text
    }
  }
}

@MainActor
private final class OwnedBackend {
  let process = Process()
  private let control = Pipe()
  private let readiness = Pipe()
  private var stopped = false

  func start(capture: DemoCaptureConfiguration) throws -> Int {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var path = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&path, &size) == 0 else {
      throw LaunchError.message("Cannot locate the demo executable")
    }
    process.executableURL = URL(
      fileURLWithPath: String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    ).resolvingSymlinksInPath()
    process.arguments = ["--backend", "--capture-directory", capture.directory.path]
    process.standardInput = control
    process.standardOutput = readiness
    process.standardError = FileHandle.standardError
    try process.run()
    try control.fileHandleForReading.close()
    try readiness.fileHandleForWriting.close()

    let deadline = ProcessInfo.processInfo.systemUptime + 15
    var data = Data()
    while ProcessInfo.processInfo.systemUptime < deadline {
      var descriptor = pollfd(fd: readiness.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
      let result = poll(&descriptor, 1, 100)
      if result < 0 {
        if errno == EINTR { continue }
        throw LaunchError.message("Failed reading backend readiness")
      }
      if result == 0 { continue }
      guard let byte = try readiness.fileHandleForReading.read(upToCount: 1), !byte.isEmpty else {
        throw LaunchError.message("Backend exited before becoming ready")
      }
      if byte == Data([10]) {
        guard let text = String(data: data, encoding: .utf8), let port = Int(text), (1...65535).contains(port) else {
          throw LaunchError.message("Invalid backend readiness response")
        }
        return port
      }
      data.append(byte)
      guard data.count <= 5 else { throw LaunchError.message("Invalid backend readiness response") }
    }
    throw LaunchError.message("Backend startup timed out after 15 seconds")
  }

  func stop() {
    guard !stopped else { return }
    stopped = true
    process.terminationHandler = nil
    try? control.fileHandleForWriting.close()
    try? readiness.fileHandleForReading.close()
    guard process.processIdentifier > 0 else { return }
    let deadline = ProcessInfo.processInfo.systemUptime + 2
    while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
      Thread.sleep(forTimeInterval: 0.01)
    }
    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    process.waitUntilExit()
  }
}
#endif
