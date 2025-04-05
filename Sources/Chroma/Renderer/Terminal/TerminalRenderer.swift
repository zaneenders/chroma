import Foundation
import SystemPackage

extension TerminalRenderer: Renderer {
  @MainActor
  func view(_ block: borrowing some Block, with state: BlockState) {
    let before = clock.now
    let size = Self.size
    let tree = block.optimizeTree(action: false)
    var walker = L2ElementRender(state: state, width: size.x, height: size.y)
    walker.walk(tree)
    Self.write(frame: walker.ascii)
    let after = clock.now
    Log.trace("\(before.duration(to: after))")
  }
}

extension TerminalRenderer {

  struct TerminalSize: Hashable {
    let x: Int
    let y: Int
  }

  fileprivate static var size: TerminalSize {
    // TODO look into the SIGWINCH signal maybe replace this function or
    // its call sites.
    var w: winsize = Self.initCStruct()
    //???: Is it possible to get a call back or notification of when the window is resized
    _ = ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w)
    // Check that we have a valid window size
    // ???: Should this throw instead?
    if w.ws_row == 0 || w.ws_col == 0 {
      return TerminalSize(x: -1, y: -1)
    } else {
      return TerminalSize(
        x: Int(w.ws_col.magnitude), y: Int(w.ws_row.magnitude))
    }
  }

}

/// This is the main renderer used to put the terminal into "raw" mode and
/// handles writing contents to the terminal on each update. It conforms to the
/// ``Renderer`` protocol to allow viewing the output of the system for testing
/// as well as allowing space for alterative backends.
struct TerminalRenderer: ~Copyable {

  var input: FileDescriptor._FileHandleAsyncByteIterator {
    FileDescriptor.standardInput.asyncByteIterator()
  }
  private let prev: termios

  init() {
    self.prev = Self.enableRawMode()
    Log.trace("Raw Mode enabled.")
    Self.setup()
  }

  /// Restore the original terminal config
  /// Clear the last frame from the screen
  deinit {
    close()
  }

  func close() {
    Log.trace("Terminal config restored.")
    Self.restore(prev)
    Self.reset()
  }

  private static func restore(_ originalConfig: termios) {
    var term = originalConfig
    // restores the original terminal state
    tcsetattr(FileHandle.standardInput.fileDescriptor, TCSAFLUSH, &term)
  }

  private static func enableRawMode() -> termios {
    // see https://stackoverflow.com/a/24335355/669586
    // init raw: termios variable
    var raw: termios = Self.initCStruct()
    // sets raw to a copy of the file handlers attributes
    tcgetattr(FileHandle.standardInput.fileDescriptor, &raw)
    // saves a copy of the original standard output file descriptor to revert back to
    let originalConfig = raw
    // ??? is this fully correct?
    // sets magical bits to enable "raw mode"
    //https://code.woboq.org/userspace/glibc/sysdeps/unix/sysv/linux/bits/termios-c_lflag.h.html
    #if os(Linux)
      raw.c_lflag &= UInt32(~(UInt32(ECHO | ICANON | IEXTEN | ISIG)))
    #else  // MacOS
      raw.c_lflag &= UInt(~(UInt32(ECHO | ICANON | IEXTEN | ISIG)))
    #endif
    // changes the file descriptor to raw mode
    tcsetattr(FileHandle.standardInput.fileDescriptor, TCSAFLUSH, &raw)
    return originalConfig
  }

  private static func initCStruct<S>() -> S {
    let structPointer = UnsafeMutablePointer<S>.allocate(capacity: 1)
    let structMemory = structPointer.pointee
    structPointer.deallocate()
    return structMemory
  }

  /// Should be called at the beginning of the program to setup the screen state correctly.
  private static func setup() {
    FileHandle.standardOutput.write(Data(setupCode.utf8))
  }

  /// Used to write the contents of of the frame to the screen.
  fileprivate static func write(frame strFrame: String) {
    clear()
    FileHandle.standardOutput.write(Data(strFrame.utf8))
  }

  /// clears the screen to setup, reset or write a new frame to the screen.
  private static func clear() {
    FileHandle.standardOutput.write(Data(Self.clearCode.utf8))
  }

  /// Resets the terminal and cursor to the screen.
  private static func reset() {
    clear()
    FileHandle.standardOutput.write(Data(Self.restCode.utf8))
  }

  private static var restCode: String {
    AnsiEscapeCode.Cursor.show.rawValue
      + AnsiEscapeCode.Cursor.Style.Block.blinking.rawValue
      + AnsiEscapeCode.home.rawValue
  }

  private static var setupCode: String {
    AnsiEscapeCode.Cursor.hide.rawValue + clearCode
  }

  private static var clearCode: String {
    AnsiEscapeCode.eraseScreen.rawValue + AnsiEscapeCode.eraseSaved.rawValue
      + AnsiEscapeCode.home.rawValue
      + AnsiEscapeCode.Cursor.Style.Block.blinking.rawValue
  }
}
