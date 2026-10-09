import Foundation
import Testing

@testable import ChromaHeadless

struct BoundedLineReaderTests {
  private func read(_ data: Data, limit: Int = 16, chunkSize: Int = 4) throws -> [BoundedLineReader.Line] {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let reader = BoundedLineReader(handle: handle, limit: limit, chunkSize: chunkSize)
    var result: [BoundedLineReader.Line] = []
    while let line = try reader.next() { result.append(line) }
    #expect(try reader.next() == nil)
    return result
  }

  @Test(arguments: [1, 2, 3, 4, 7, 4096])
  func framingAcrossChunks(chunkSize: Int) throws {
    let lines = ["", "a", "bc", "def", "ghij", "klmno", "p\r", "", "tail"]
    #expect(
      try read(Data(lines.joined(separator: "\n").utf8), chunkSize: chunkSize)
        == lines.map { .bytes(Data($0.utf8)) })
  }

  @Test(arguments: [1, 3, 4, 5, 4096])
  func limitAndOversizedRecovery(chunkSize: Int) throws {
    let data = Data("123\n1234\n12345\n\nokay\n".utf8)
    #expect(
      try read(data, limit: 4, chunkSize: chunkSize)
        == [.bytes(Data("123".utf8)), .bytes(Data("1234".utf8)), .oversized, .bytes(Data()), .bytes(Data("okay".utf8))])
  }

  @MainActor @Test func maximumLengthBoundaries() throws {
    let limit = HeadlessSession.maximumLineBytes
    let exact = Data(repeating: 97, count: limit)
    #expect(
      try read(exact + Data([10]) + exact + Data([97, 10, 98, 10]), limit: limit) == [
        .bytes(exact), .oversized, .bytes(Data([98])),
      ])
  }

  @Test func oversizedLineSpansManyChunks() throws {
    let data = Data(repeating: 120, count: 2_000_000) + Data("\nvalid\n".utf8)
    #expect(try read(data, chunkSize: 4096) == [.oversized, .bytes(Data("valid".utf8))])
  }

  @Test func eofAndZeroLimit() throws {
    #expect(try read(Data()) == [])
    #expect(try read(Data([10])) == [.bytes(Data())])
    #expect(try read(Data("1234".utf8), limit: 4) == [.bytes(Data("1234".utf8))])
    #expect(try read(Data("12345".utf8), limit: 4) == [.oversized])
    #expect(try read(Data("\na\n".utf8), limit: 0) == [.bytes(Data()), .oversized])
  }

  @Test func retainsBytesWithoutUnicodeDecoding() throws {
    let unicode = Data("é🙂\u{2028}\u{2029}\u{85}".utf8)
    let invalid = Data([0xFF, 0xC0, 0x80])
    #expect(try read(unicode + Data([10]) + invalid, chunkSize: 1) == [.bytes(unicode), .bytes(invalid)])
  }

  @Test func readErrorsAreThrown() throws {
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
    defer { try? handle.close() }
    let reader = BoundedLineReader(handle: handle, limit: 16)
    #expect(throws: POSIXError(.EBADF)) { try reader.next() }
  }
}
