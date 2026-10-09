import Foundation
import Synchronization

#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Serializes reads and retains at most one bounded line plus a fixed-size chunk.
final class BoundedLineReader: Sendable {
  enum Line: Sendable, Equatable {
    case bytes(Data)
    case oversized
  }

  private struct Buffer {
    var bytes: [UInt8]
    var start = 0
    var end = 0
    var eof = false
  }

  private let handle: FileHandle
  private let limit: Int
  private let buffer: Mutex<Buffer>

  init(handle: FileHandle, limit: Int, chunkSize: Int = 4096) {
    precondition(limit >= 0 && chunkSize > 0)
    self.handle = handle
    self.limit = limit
    buffer = Mutex(Buffer(bytes: [UInt8](repeating: 0, count: chunkSize)))
  }

  func next() throws -> Line? {
    try buffer.withLock { buffer in
      var bytes = Data()
      var oversized = false
      var received = false
      while true {
        if buffer.start == buffer.end {
          if buffer.eof { break }
          // Foundation's read(upToCount:) may wait to fill its requested size.
          // One POSIX read returns whatever is available, even while stdin stays open.
          let count = buffer.bytes.withUnsafeMutableBytes { storage in
            read(handle.fileDescriptor, storage.baseAddress, storage.count)
          }
          if count < 0 {
            if errno == EINTR { continue }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
          }
          if count == 0 {
            buffer.eof = true
            break
          }
          buffer.start = 0
          buffer.end = count
        }
        let newline = buffer.bytes[buffer.start..<buffer.end].firstIndex(of: 10)
        let end = newline ?? buffer.end
        let count = end - buffer.start
        received = true
        if !oversized {
          let retained = min(count, limit - bytes.count)
          bytes.append(contentsOf: buffer.bytes[buffer.start..<(buffer.start + retained)])
          oversized = retained < count
        }
        buffer.start = end + (newline == nil ? 0 : 1)
        if newline != nil { return oversized ? .oversized : .bytes(bytes) }
      }
      guard received else { return nil }
      return oversized ? .oversized : .bytes(bytes)
    }
  }
}
