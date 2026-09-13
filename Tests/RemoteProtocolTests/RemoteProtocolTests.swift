import Chroma
import Foundation
import NIOCore
import RemoteProtocol
import Testing

@Suite("Remote wire protocol")
struct RemoteProtocolTests {
  @Test func rejectsPreviousFontFaceWireFormat() throws {
    var bytes = try RemoteWire.encode(.requestFrame)
    bytes.setInteger(UInt16(3), at: 4, endianness: .little)
    #expect(RemoteWire.version == 5)
    #expect(throws: RemoteProtocolError.unsupportedVersion(3)) {
      _ = try RemoteWire.decode(from: &bytes)
    }
  }

  @Test func messageTypeNumbersAndHeaderStayWireCompatible() throws {
    let cases: [(RemoteMessage, UInt16, UInt32)] = [
      (.viewport(Size(width: 800, height: 600)), 1, 8),
      (.input(sequence: 7, state: InputState()), 2, 41),
      (.frame(id: 9, inputSequence: 7, viewport: Size(width: 800, height: 600), commands: []), 3, 28),
      (.requestFrame, 4, 0),
    ]

    for (message, expectedType, expectedPayloadLength) in cases {
      let bytes = try RemoteWire.encode(message)
      #expect(integer(UInt32.self, in: bytes, at: 0) == RemoteWire.magic)
      #expect(integer(UInt16.self, in: bytes, at: 4) == RemoteWire.version)
      #expect(integer(UInt16.self, in: bytes, at: 6) == expectedType)
      #expect(integer(UInt32.self, in: bytes, at: 8) == expectedPayloadLength)
      #expect(bytes.readableBytes == 12 + Int(expectedPayloadLength))
    }
  }

  @Test func simpleCounterExchangeRoundTripsAsAFragmentedByteStream() throws {
    let viewport = RemoteMessage.viewport(Size(width: 800, height: 520))
    let press = RemoteMessage.input(
      sequence: 1,
      state: InputState(
        pointerPosition: Point(x: 515, y: 260),
        pointerPressPosition: Point(x: 515, y: 260),
        pointerDown: true, pointerPressed: true,
        commands: [.action(.activate)]))
    let release = RemoteMessage.input(
      sequence: 2,
      state: InputState(
        pointerPosition: Point(x: 515, y: 260),
        pointerPressPosition: Point(x: 515, y: 260),
        pointerReleased: true))
    let frame = RemoteMessage.frame(
      id: 3, inputSequence: 2, viewport: Size(width: 800, height: 520),
      commands: [
        .fillRect(rect: Rect(x: 0, y: 0, width: 800, height: 520), color: .black),
        .text(
          position: Point(x: 275, y: 180), text: "Remote button count: 1",
          color: .white, scale: 0.9),
      ])
    let messages: [RemoteMessage] = [viewport, .requestFrame, press, release, frame]

    var stream = ByteBuffer()
    for message in messages {
      var encoded = try RemoteWire.encode(message)
      stream.writeBuffer(&encoded)
    }

    var receiveBuffer = ByteBuffer()
    var decoded: [RemoteMessage] = []
    while stream.readableBytes > 0 {
      let chunkLength = min(3, stream.readableBytes)
      guard var chunk = stream.readSlice(length: chunkLength) else {
        Issue.record("Failed to read a complete test stream chunk")
        break
      }
      receiveBuffer.writeBuffer(&chunk)
      while let message = try RemoteWire.decode(from: &receiveBuffer) {
        decoded.append(message)
      }
      receiveBuffer.discardReadBytes()
    }

    #expect(decoded == messages)
    #expect(receiveBuffer.readableBytes == 0)
  }

  @Test func everyInputCommandAndTextEventRoundTrips() throws {
    let textEvents: [TextEditEvent] = [
      .insert("héllo 👋"), .backspace, .deleteForward, .moveCaretLeft, .moveCaretRight,
      .moveCaretUp, .moveCaretDown, .selectCaretUp, .selectCaretDown, .moveCaretToStart,
      .moveCaretToEnd, .selectAll, .copy, .cut, .paste, .submit, .endEditing,
    ]
    let commands: [Command] = [
      .navigation(.up), .navigation(.down), .navigation(.left), .navigation(.right),
      .navigation(.in), .navigation(.out), .navigation(.next), .navigation(.previous),
      .navigation(.pageUp), .navigation(.pageDown), .navigation(.home), .navigation(.end),
      .action(.activate), .action(.submit), .action(.cancel), .action(.dismiss),
      .editing(.insert("wire text")), .editing(.selectAll),
      .application(CommandID("counter.increment")),
    ]
    let message = RemoteMessage.input(
      sequence: .max,
      state: InputState(
        pointerPosition: Point(x: 1.25, y: -2.5),
        pointerPressPosition: Point(x: 3.75, y: 4.5),
        pointerDown: true, pointerPressed: true, pointerReleased: true,
        scrollDelta: Point(x: -8, y: 13), commands: commands, textEvents: textEvents))

    #expect(try roundTrip(message) == message)
  }

  @Test func everyDrawCommandRoundTripsIncludingImagePixels() throws {
    let image = try ImageResource(
      id: ImageID("test.rgba"), generation: 42, width: 2, height: 1,
      rgba8: Data([255, 0, 0, 255, 0, 255, 0, 128]))
    let rect = Rect(x: 1, y: 2, width: 30, height: 40)
    let radii = CornerRadii(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4)
    let color = Color(r: 0.1, g: 0.2, b: 0.3, a: 0.4)
    let commands: [DrawCommand] = [
      .fillRect(rect: rect, color: color),
      .strokeRect(rect: rect, width: 2.5, color: color),
      .fillRoundedRect(rect: rect, radii: radii, color: color),
      .strokeRoundedRect(rect: rect, radii: radii, width: 3.5, color: color),
      .text(position: Point(x: -1, y: 9), text: "CHROMA 🟨", color: color, scale: 1.25),
      .image(rect: rect, image: image, scaling: .cover, alignment: ImageAlignment(x: 0.25, y: 0.75)),
      .pushClip(rect), .popClip,
    ]
    let message = RemoteMessage.frame(
      id: 123, inputSequence: 99, viewport: Size(width: 1920, height: 1080), commands: commands)

    #expect(try roundTrip(message) == message)
  }

  @Test func decoderWaitsForACompleteHeaderAndPayloadWithoutConsumingBytes() throws {
    let message = RemoteMessage.frame(
      id: 1, inputSequence: 0, viewport: Size(width: 64, height: 48),
      commands: [.fillRect(rect: Rect(x: 0, y: 0, width: 64, height: 48), color: .yellow)])
    let encoded = try RemoteWire.encode(message)
    let allBytes = try #require(encoded.getBytes(at: encoded.readerIndex, length: encoded.readableBytes))

    for prefixLength in 0..<allBytes.count {
      var prefix = ByteBuffer(bytes: allBytes.prefix(prefixLength))
      let readerIndex = prefix.readerIndex
      #expect(try RemoteWire.decode(from: &prefix) == nil)
      #expect(prefix.readerIndex == readerIndex)
      #expect(prefix.readableBytes == prefixLength)
    }

    var complete = ByteBuffer(bytes: allBytes)
    #expect(try RemoteWire.decode(from: &complete) == message)
    #expect(complete.readableBytes == 0)
  }

  @Test func decoderLeavesTheNextFramedMessageInTheBuffer() throws {
    let first = RemoteMessage.viewport(Size(width: 320, height: 200))
    let second = RemoteMessage.requestFrame
    var bytes = try RemoteWire.encode(first)
    var secondBytes = try RemoteWire.encode(second)
    bytes.writeBuffer(&secondBytes)

    #expect(try RemoteWire.decode(from: &bytes) == first)
    #expect(try RemoteWire.decode(from: &bytes) == second)
    #expect(try RemoteWire.decode(from: &bytes) == nil)
  }

  @Test func invalidHeadersAreRejected() throws {
    var invalidMagic = header(magic: 0, version: RemoteWire.version, type: 4, length: 0)
    #expect(throws: RemoteProtocolError.invalidMagic) { try RemoteWire.decode(from: &invalidMagic) }

    var invalidVersion = header(magic: RemoteWire.magic, version: RemoteWire.version + 1, type: 4, length: 0)
    #expect(throws: RemoteProtocolError.unsupportedVersion(RemoteWire.version + 1)) {
      try RemoteWire.decode(from: &invalidVersion)
    }

    var unknownMessage = header(magic: RemoteWire.magic, version: RemoteWire.version, type: .max, length: 0)
    #expect(throws: RemoteProtocolError.unknownMessage(.max)) {
      try RemoteWire.decode(from: &unknownMessage)
    }

    var oversized = header(
      magic: RemoteWire.magic, version: RemoteWire.version, type: 4,
      length: UInt32(RemoteWire.maximumPayloadBytes + 1))
    #expect(throws: RemoteProtocolError.messageTooLarge(RemoteWire.maximumPayloadBytes + 1)) {
      try RemoteWire.decode(from: &oversized)
    }
  }

  @Test func malformedPayloadsAndUnknownCommandsAreRejected() throws {
    var impossibleCountPayload = ByteBuffer()
    impossibleCountPayload.writeInteger(UInt64(1), endianness: .little)
    impossibleCountPayload.writeInteger(UInt64(0), endianness: .little)
    impossibleCountPayload.writeInteger(Float(10).bitPattern, endianness: .little)
    impossibleCountPayload.writeInteger(Float(10).bitPattern, endianness: .little)
    impossibleCountPayload.writeInteger(UInt32.max, endianness: .little)
    var impossibleCountFrame = header(
      magic: RemoteWire.magic, version: RemoteWire.version, type: 3,
      length: UInt32(impossibleCountPayload.readableBytes))
    impossibleCountFrame.writeBuffer(&impossibleCountPayload)
    #expect(throws: RemoteProtocolError.malformedMessage) {
      try RemoteWire.decode(from: &impossibleCountFrame)
    }

    var requestWithPayload = header(magic: RemoteWire.magic, version: RemoteWire.version, type: 4, length: 1)
    requestWithPayload.writeInteger(UInt8(0))
    #expect(throws: RemoteProtocolError.malformedMessage) {
      try RemoteWire.decode(from: &requestWithPayload)
    }

    var framePayload = ByteBuffer()
    framePayload.writeInteger(UInt64(1), endianness: .little)
    framePayload.writeInteger(UInt64(0), endianness: .little)
    framePayload.writeInteger(Float(10).bitPattern, endianness: .little)
    framePayload.writeInteger(Float(10).bitPattern, endianness: .little)
    framePayload.writeInteger(UInt32(1), endianness: .little)
    framePayload.writeInteger(UInt8.max)
    var unknownCommand = header(
      magic: RemoteWire.magic, version: RemoteWire.version, type: 3,
      length: UInt32(framePayload.readableBytes))
    unknownCommand.writeBuffer(&framePayload)
    #expect(throws: RemoteProtocolError.unknownCommand(.max)) {
      try RemoteWire.decode(from: &unknownCommand)
    }
  }

  private func roundTrip(_ message: RemoteMessage) throws -> RemoteMessage {
    var bytes = try RemoteWire.encode(message)
    let result = try RemoteWire.decode(from: &bytes)
    guard let decoded = result else {
      Issue.record("Encoded message did not decode as a complete frame")
      throw RemoteProtocolError.malformedMessage
    }
    #expect(bytes.readableBytes == 0)
    return decoded
  }

  private func integer<T: FixedWidthInteger>(
    _ type: T.Type, in buffer: ByteBuffer, at offset: Int
  ) -> T? {
    buffer.getInteger(at: buffer.readerIndex + offset, endianness: .little)
  }

  private func header(magic: UInt32, version: UInt16, type: UInt16, length: UInt32) -> ByteBuffer {
    var buffer = ByteBuffer()
    buffer.writeInteger(magic, endianness: .little)
    buffer.writeInteger(version, endianness: .little)
    buffer.writeInteger(type, endianness: .little)
    buffer.writeInteger(length, endianness: .little)
    return buffer
  }
}

@Test func waitForFrameRoundTrips() throws {
  var bytes = try RemoteWire.encode(.waitForFrame)
  #expect(try RemoteWire.decode(from: &bytes) == .waitForFrame)
  #expect(bytes.readableBytes == 0)
}
