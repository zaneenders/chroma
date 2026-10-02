import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Keep ordinary application print() calls out of the machine-readable channel.
/// Process-wide: use only from the executable entry point, before creating the App.
final class StandardIOChannels {
  let output: FileHandle
  private let savedOutput: Int32
  private let previousPipeHandler: (@convention(c) (Int32) -> Void)?

  init() throws {
    fflush(nil)
    savedOutput = dup(STDOUT_FILENO)
    guard savedOutput >= 0 else { throw POSIXError(.EBADF) }
    guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
      _ = close(savedOutput)
      throw POSIXError(.EBADF)
    }
    previousPipeHandler = signal(SIGPIPE, SIG_IGN)
    output = FileHandle(fileDescriptor: savedOutput, closeOnDealloc: false)
  }

  deinit {
    fflush(nil)
    _ = dup2(savedOutput, STDOUT_FILENO)
    _ = close(savedOutput)
    _ = signal(SIGPIPE, previousPipeHandler)
  }
}

func failProcess(_ error: any Error) -> Never {
  try? FileHandle.standardError.write(contentsOf: Data("chroma-headless: \(error)\n".utf8))
  exit(EXIT_FAILURE)
}
