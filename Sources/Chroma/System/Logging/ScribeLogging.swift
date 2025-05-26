import Foundation
import Logging
import SystemPackage

struct ChromaLogging: LogHandler {

  let file_path: FilePath
  var logLevel: Logger.Level
  var metadata: Logging.Logger.Metadata
  var dateFormatter = DateFormatter()
  private let tracing: Bool
  private let write_to_file: Bool
  internal init(
    file_path: FilePath, logLevel: Logger.Level,
    metadata: Logger.Metadata = [:], tracing: Bool,
    write_to_file: Bool
  ) {
    self.file_path = file_path
    self.metadata = metadata
    self.logLevel = logLevel
    self.tracing = tracing
    self.write_to_file = write_to_file
    self.dateFormatter.dateFormat = "mm_ss_SSSS"
  }

  subscript(metadataKey _: String) -> Logging.Logger.Metadata.Value? {
    get {
      nil
    }
    set(newValue) {
    }
  }

  func log(
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    switch (tracing, write_to_file) {
    case (_, true):
      logFile(
        file_path, tracing, level: level, message: message, metadata: metadata, source: source,
        file: file, function: function, line: line)
    case (true, false):
      tracing(level, message)
    case (false, false):
      terminal(level, message)
    }
  }

  // Hacky log to file.
  private func logFile(
    _ file_path: FilePath,
    _ tracing: Bool,
    level: Logger.Level,
    message: Logger.Message,
    metadata: Logger.Metadata?,
    source: String,
    file: String,
    function: String,
    line: UInt
  ) {
    var out: String = ""
    let levelStr = "\(level)".uppercased()
    out += "[\(levelStr)]"
    switch tracing {
    case true:
      out += " <trace:\(_ChromaLog.id)>"
    case false:
      ()
    }
    // out += "<module:\(source)>"
    out += " <file:\(file)>"
    out += " <line:\(line)>"
    out += " <func:\(function)>"

    // let formattedDate = dateFormatter.string(from: Date.now)
    // out += " <time:\(formattedDate)>"
    out += " \(message)\n"
    do {
      // I wonder if I should open this at the beginning of the program instead of each log call.
      try file_path.appendAtEnd(out)
    } catch {
      fatalError("Unable to create log file: \(file_path.string)")
    }
  }

  private func terminal(_ level: Logger.Level, _ message: Logger.Message) {
    let color: Shell.Color
    switch level {
    case .trace:
      color = .default
    case .debug:
      color = .teal
    case .info:
      color = .green
    case .notice:
      color = .purple
    case .warning:
      color = .yellow
    case .error:
      color = .orange
    case .critical:
      color = .red
    }
    print(Shell.wrap("\(message)", color, .default))
  }

  private func tracing(_ level: Logger.Level, _ message: Logger.Message) {
    print("\(_ChromaLog.id):[\("\(level)".uppercased())]\(message)")
  }
}

extension FilePath {
  func appendAtEnd(_ contents: String) throws {
    let fd = try FileDescriptor.open(
      self, .readWrite, options: [.append, .create], permissions: .ownerReadWrite)
    try fd.writeAll(contents.utf8)
    try fd.close()
  }
}
