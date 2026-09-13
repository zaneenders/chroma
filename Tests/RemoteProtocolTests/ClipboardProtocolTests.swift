import Chroma
import Foundation
import NIOCore
import RemoteProtocol
import Testing

@Suite("Remote keys and clipboard")
struct ClipboardProtocolTests {
  @Test func portableKeysAndClipboardRoundTripInOrder() throws {
    let messages: [RemoteMessage] = [
      .key(sequence: 1, event: RemoteKeyEvent(chord: KeyChord("a", modifiers: .command))),
      .key(sequence: 2, event: RemoteKeyEvent(chord: KeyChord(.leftArrow))),
      .key(sequence: 3, event: RemoteKeyEvent(chord: nil, text: "café 👩🏽‍💻")),
      .clipboard(ClipboardTransfer(id: 3)),
      .clipboard(ClipboardTransfer(id: 3, isReply: true, text: "Hello\n世界")),
      .clipboard(ClipboardTransfer(id: 4, text: "Copy me")),
      .clipboard(ClipboardTransfer(id: 4, isReply: true, success: false)),
    ]
    var wire = ByteBuffer()
    for message in messages {
      var encoded = try RemoteWire.encode(message)
      wire.writeBuffer(&encoded)
    }
    var partial = ByteBuffer()
    var received: [RemoteMessage] = []
    while let byte: UInt8 = wire.readInteger() {
      partial.writeInteger(byte)
      while let message = try RemoteWire.decode(from: &partial) { received.append(message) }
    }
    #expect(received == messages)
  }

  @Test(arguments: [false, true])
  func clipboardAcceptsExactlyOneMiBEncodedPayload(isReply: Bool) throws {
    let transfer = try clipboardTransfer(encodedBytes: RemoteWire.maximumClipboardBytes, isReply: isReply)
    #expect(try JSONEncoder().encode(transfer).count == 1024 * 1024)
    var wire = try RemoteWire.encode(.clipboard(transfer))
    #expect(wire.readableBytes == 1024 * 1024 + 12)
    #expect(try RemoteWire.decode(from: &wire) == .clipboard(transfer))
    #expect(wire.readableBytes == 0)
  }

  @Test(arguments: [1, 1024], [false, true])
  func clipboardRejectsEncodedPayloadAboveOneMiB(excess: Int, isReply: Bool) throws {
    let size = RemoteWire.maximumClipboardBytes + excess
    let transfer = try clipboardTransfer(encodedBytes: size, isReply: isReply)
    let payload = try JSONEncoder().encode(transfer)
    #expect(payload.count == size)
    #expect(throws: RemoteProtocolError.messageTooLarge(size)) {
      _ = try RemoteWire.encode(.clipboard(transfer))
    }

    var wire = ByteBuffer()
    wire.writeInteger(RemoteWire.magic, endianness: .little)
    wire.writeInteger(RemoteWire.version, endianness: .little)
    wire.writeInteger(UInt16(6), endianness: .little)
    wire.writeInteger(UInt32(payload.count), endianness: .little)
    wire.writeBytes(payload)
    #expect(throws: RemoteProtocolError.messageTooLarge(size)) {
      _ = try RemoteWire.decode(from: &wire)
    }
  }

  @Test(arguments: [1024 * 1024, 1024 * 1024 + 1])
  func clipboardRejectsOneMiBOrMoreOfRawText(textBytes: Int) throws {
    let transfer = ClipboardTransfer(id: 1, text: String(repeating: "x", count: textBytes))
    let encodedBytes = try JSONEncoder().encode(transfer).count
    #expect(encodedBytes > RemoteWire.maximumClipboardBytes)
    #expect(throws: RemoteProtocolError.messageTooLarge(encodedBytes)) {
      _ = try RemoteWire.encode(.clipboard(transfer))
    }
  }

  private func clipboardTransfer(encodedBytes: Int, isReply: Bool) throws -> ClipboardTransfer {
    var transfer = ClipboardTransfer(id: 1, isReply: isReply, text: "")
    let overhead = try JSONEncoder().encode(transfer).count
    transfer.text = String(repeating: "x", count: encodedBytes - overhead)
    return transfer
  }

  @Test func clipboardAcceptsLargeASCIISelection() throws {
    let message = RemoteMessage.clipboard(
      ClipboardTransfer(id: 1, text: String(repeating: "x", count: 200 * 1024)))
    var wire = try RemoteWire.encode(message)
    #expect(try RemoteWire.decode(from: &wire) == message)
  }

  @Test func clipboardLimitIncludesJSONEscaping() {
    let text = String(repeating: "\u{0000}", count: 200 * 1024)
    #expect(text.utf8.count < RemoteWire.maximumClipboardBytes)
    #expect(throws: RemoteProtocolError.self) {
      _ = try RemoteWire.encode(.clipboard(ClipboardTransfer(id: 1, text: text)))
    }
  }

  @Test func appBindingsCanOverrideAndDisable() {
    let base = KeyBindings { bind("q", to: .editing(.copy)) }
    let editing = base.overlay {
      bind("q", to: .editing(.paste))
      disable("a", modifiers: .command)
    }
    #expect(base.command(for: KeyChord("q"))! == .editing(.copy))
    #expect(editing.command(for: KeyChord("q"))! == .editing(.paste))
    #expect(editing.command(for: KeyChord("a", modifiers: .command))! == nil)
    #expect(editing.command(for: KeyChord("v", modifiers: .command)) == nil)
  }
}
