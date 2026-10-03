import Foundation

/// Only one detached read is active at a time. Buffering never grows with an oversized line.
final class BoundedLineReader: Sendable {
  enum Line: Sendable {
    case bytes(Data)
    case oversized
  }

  private let handle: FileHandle
  private let limit: Int

  init(handle: FileHandle, limit: Int) {
    self.handle = handle
    self.limit = limit
  }

  func next() throws -> Line? {
    var bytes = Data()
    var oversized = false
    var received = false
    while let byte = try handle.read(upToCount: 1), !byte.isEmpty {
      received = true
      if byte[0] == 10 { return oversized ? .oversized : .bytes(bytes) }
      if bytes.count < limit {
        bytes.append(byte)
      } else {
        oversized = true
      }
    }
    guard received else { return nil }
    return oversized ? .oversized : .bytes(bytes)
  }
}
