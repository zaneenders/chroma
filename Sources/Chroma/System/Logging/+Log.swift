import Logging
import SystemPackage

/// Globally configure how logging is to be recorded.
func enableLogging(
  file_path: FilePath, logLevel: Logger.Level, tracing: Bool, write_to_file: Bool
) {
  LoggingSystem.bootstrap { _ in
    ChromaLogging(
      file_path: file_path, logLevel: logLevel, tracing: tracing, write_to_file: write_to_file)
  }
}

/*
Beta because im not sure how I wanna handle logging. I added logging to the
system to get better visibility into what is going on to use along side
debugging and testing tools.
*/
@available(*, deprecated, message: "BETA")
public enum _ChromaLog {
  @TaskLocal
  static var id: UInt128 = UInt128.random(in: UInt128.min..<UInt128.max)

  private static let logger = Logger(label: "chroma")

  public static func trace(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    logger.trace(
      message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
  }

  public static func debug(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    logger.debug(
      message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
  }

  public static func info(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    logger.info(
      message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
  }

  public static func notice(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    logger.notice(
      message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
  }

  public static func warning(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    logger.warning(
      message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
  }

  public static func error(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    logger.error(
      message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
  }

  public static func critical(
    _ message: @autoclosure () -> Logger.Message,
    metadata: @autoclosure () -> Logger.Metadata? = nil,
    source: @autoclosure () -> String? = nil,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line
  ) {
    logger.critical(
      message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
  }
}

func clearLog(_ file_path: FilePath) {
  do {
    let fd = try FileDescriptor.open(
      file_path, .readWrite, options: [.truncate, .create], permissions: .ownerReadWrite)
    try fd.close()
  } catch {
    _ChromaLog.critical("Unable to create log file: \(file_path.string)")
  }
}
