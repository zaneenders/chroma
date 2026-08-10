#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class TerminalSession {
  enum Error: Swift.Error { case notTTY, termios }

  private var saved = termios()
  private var isInstalled = false

  init() throws {
    guard isatty(STDIN_FILENO) != 0, isatty(STDOUT_FILENO) != 0 else { throw Error.notTTY }
    guard tcgetattr(STDIN_FILENO, &saved) == 0 else { throw Error.termios }
    var raw = saved
    cfmakeraw(&raw)
    guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else { throw Error.termios }
    isInstalled = true
    write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?2004h\u{1B}[2J\u{1B}[H")
  }

  deinit { restore() }

  func restore() {
    guard isInstalled else { return }
    isInstalled = false
    write("\u{1B}[0m\u{1B}[?2004l\u{1B}[?25h\u{1B}[?1049l")
    _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &saved)
  }

  func windowSize() -> (columns: Int, rows: Int) {
    var size = winsize()
    if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &size) == 0,
      size.ws_col > 0, size.ws_row > 0
    {
      return (Int(size.ws_col), Int(size.ws_row))
    }
    return (80, 24)
  }

  func read(timeoutMilliseconds: Int32) -> [UInt8]? {
    var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    let result = poll(&descriptor, 1, timeoutMilliseconds)
    guard result > 0, descriptor.revents & Int16(POLLIN) != 0 else { return nil }
    var bytes = [UInt8](repeating: 0, count: 4096)
    let count = bytes.withUnsafeMutableBytes { raw in
      DarwinOrGlibcRead(STDIN_FILENO, raw.baseAddress!, raw.count)
    }
    guard count > 0 else { return [] }
    return Array(bytes.prefix(count))
  }

  func write(_ string: String) {
    let bytes = Array(string.utf8)
    bytes.withUnsafeBytes { raw in
      guard var pointer = raw.baseAddress else { return }
      var remaining = raw.count
      while remaining > 0 {
        let count = DarwinOrGlibcWrite(STDOUT_FILENO, pointer, remaining)
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { return }
        pointer = pointer.advanced(by: count)
        remaining -= count
      }
    }
  }
}

private func DarwinOrGlibcRead(
  _ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int
) -> Int {
  #if canImport(Darwin)
  Darwin.read(fd, buffer, count)
  #else
  Glibc.read(fd, buffer, count)
  #endif
}

private func DarwinOrGlibcWrite(
  _ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int
) -> Int {
  #if canImport(Darwin)
  Darwin.write(fd, buffer, count)
  #else
  Glibc.write(fd, buffer, count)
  #endif
}

struct TerminalPresenter {
  private var previous: TerminalFrame?

  mutating func encode(_ frame: TerminalFrame) -> String {
    var output = ""
    var lastForeground: TerminalRGB?
    var lastBackground: TerminalRGB?
    for row in 0..<frame.rows {
      let rowChanged =
        previous == nil || previous!.columns != frame.columns
        || previous!.rows != frame.rows
        || (0..<frame.columns).contains { previous![column: $0, row: row] != frame[column: $0, row: row] }
      guard rowChanged else { continue }
      output += "\u{1B}[\(row + 1);1H"
      for column in 0..<frame.columns {
        let cell = frame[column: column, row: row]
        if lastBackground != cell.background {
          output += "\u{1B}[48;2;\(cell.background.r);\(cell.background.g);\(cell.background.b)m"
          lastBackground = cell.background
        }
        if lastForeground != cell.foreground {
          output += "\u{1B}[38;2;\(cell.foreground.r);\(cell.foreground.g);\(cell.foreground.b)m"
          lastForeground = cell.foreground
        }
        output.append(cell.glyph)
      }
    }
    output += "\u{1B}[0m"
    previous = frame
    return output
  }
}
