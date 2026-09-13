import Chroma
import Foundation
import NIOCore

public enum RemoteProtocolError: Error, Equatable, Sendable {
  case invalidMagic
  case unsupportedVersion(UInt16)
  case unknownMessage(UInt16)
  case unknownCommand(UInt8)
  case malformedMessage
  case messageTooLarge(Int)
  case stringTooLarge(Int)
  case imageTooLarge(Int)
}

public enum RemoteMessage: Equatable, Sendable {
  case key(sequence: UInt64, event: RemoteKeyEvent)
  case clipboard(ClipboardTransfer)
  case viewport(Size)
  case input(sequence: UInt64, state: InputState)
  case requestFrame
  case waitForFrame
  case frameRate(Float)
  case frameUnchanged
  case frame(id: UInt64, inputSequence: UInt64, viewport: Size, commands: [DrawCommand])
}

public enum RemoteWire {
  public static let magic: UInt32 = 0x4348_524D
  public static let version: UInt16 = 5
  public static let maximumClipboardBytes = 1024 * 1024
  public static let maximumPayloadBytes = 64 * 1024 * 1024
  public static let maximumCommandsPerFrame = 1_000_000

  private enum MessageType: UInt16 {
    case frameRate = 7
    case frameUnchanged = 8
    case key = 5
    case clipboard = 6
    case viewport = 1
    case input = 2
    case frame = 3
    case waitForFrame = 9
    case requestFrame = 4
  }

  public static func encode(
    _ message: RemoteMessage, allocator: ByteBufferAllocator = .init()
  ) throws -> ByteBuffer {
    var images = RemoteImageCache()
    return try encode(message, allocator: allocator, images: &images)
  }

  public static func decode(from buffer: inout ByteBuffer) throws -> RemoteMessage? {
    var images = RemoteImageCache()
    return try decode(from: &buffer, images: &images)
  }

  public static func encode(
    _ message: RemoteMessage, allocator: ByteBufferAllocator = .init(), images: inout RemoteImageCache
  ) throws -> ByteBuffer {
    var workingImages = images
    var payload = allocator.buffer(capacity: 1024)
    let type: MessageType
    switch message {
    case .key(let sequence, let event):
      type = .key
      payload.writeInteger(sequence, endianness: .little)
      payload.writeBytes(try JSONEncoder().encode(event))
    case .clipboard(let transfer):
      type = .clipboard
      let data = try JSONEncoder().encode(transfer)
      guard data.count <= Self.maximumClipboardBytes else { throw RemoteProtocolError.messageTooLarge(data.count) }
      payload.writeBytes(data)
    case .viewport(let size):
      type = .viewport
      payload.writeSize(size)
    case .input(let sequence, let state):
      type = .input
      payload.writeInteger(sequence, endianness: .little)
      try payload.writeInput(state)
    case .frameRate(let fps):
      guard fps.isFinite, fps >= 1, fps <= 240 else { throw RemoteProtocolError.malformedMessage }
      type = .frameRate
      payload.writeFloat(fps)
    case .frameUnchanged:
      type = .frameUnchanged
    case .waitForFrame:
      type = .waitForFrame
    case .requestFrame:
      type = .requestFrame
    case .frame(let id, let inputSequence, let viewport, let commands):
      type = .frame
      payload.writeInteger(id, endianness: .little)
      payload.writeInteger(inputSequence, endianness: .little)
      payload.writeSize(viewport)
      guard commands.count <= min(Int(UInt32.max), maximumCommandsPerFrame) else {
        throw RemoteProtocolError.messageTooLarge(commands.count)
      }
      payload.writeInteger(UInt32(commands.count), endianness: .little)
      for command in commands { try payload.writeCommand(command, images: &workingImages) }
    }
    guard payload.readableBytes <= maximumPayloadBytes else {
      throw RemoteProtocolError.messageTooLarge(payload.readableBytes)
    }
    var result = allocator.buffer(capacity: payload.readableBytes + 12)
    result.writeInteger(magic, endianness: .little)
    result.writeInteger(version, endianness: .little)
    result.writeInteger(type.rawValue, endianness: .little)
    result.writeInteger(UInt32(payload.readableBytes), endianness: .little)
    result.writeBuffer(&payload)
    images = workingImages
    return result
  }

  public static func decode(from buffer: inout ByteBuffer, images: inout RemoteImageCache) throws -> RemoteMessage? {
    guard buffer.readableBytes >= 12 else { return nil }
    guard
      let magic: UInt32 = buffer.getInteger(at: buffer.readerIndex, endianness: .little),
      let version: UInt16 = buffer.getInteger(at: buffer.readerIndex + 4, endianness: .little),
      let rawType: UInt16 = buffer.getInteger(at: buffer.readerIndex + 6, endianness: .little),
      let length: UInt32 = buffer.getInteger(at: buffer.readerIndex + 8, endianness: .little)
    else { return nil }
    guard magic == self.magic else { throw RemoteProtocolError.invalidMagic }
    guard version == self.version else { throw RemoteProtocolError.unsupportedVersion(version) }
    guard Int(length) <= maximumPayloadBytes else {
      throw RemoteProtocolError.messageTooLarge(Int(length))
    }
    guard buffer.readableBytes >= 12 + Int(length) else { return nil }
    buffer.moveReaderIndex(forwardBy: 12)
    guard var payload = buffer.readSlice(length: Int(length)) else {
      throw RemoteProtocolError.malformedMessage
    }
    guard let type = MessageType(rawValue: rawType) else {
      throw RemoteProtocolError.unknownMessage(rawType)
    }
    var workingImages = images
    let message: RemoteMessage
    switch type {
    case .key:
      let sequence = try payload.read(UInt64.self)
      message = .key(
        sequence: sequence,
        event: try JSONDecoder().decode(
          RemoteKeyEvent.self, from: Data(payload.readBytes(length: payload.readableBytes)!)))
    case .clipboard:
      guard payload.readableBytes <= Self.maximumClipboardBytes else {
        throw RemoteProtocolError.messageTooLarge(payload.readableBytes)
      }
      message = .clipboard(
        try JSONDecoder().decode(ClipboardTransfer.self, from: Data(payload.readBytes(length: payload.readableBytes)!)))
    case .viewport:
      message = .viewport(try payload.readSize())
    case .input:
      message = .input(sequence: try payload.read(UInt64.self), state: try payload.readInput())
    case .frameRate:
      let fps = try payload.readFloat()
      guard fps.isFinite, fps >= 1, fps <= 240 else { throw RemoteProtocolError.malformedMessage }
      message = .frameRate(fps)
    case .frameUnchanged:
      message = .frameUnchanged
    case .waitForFrame:
      message = .waitForFrame
    case .requestFrame:
      message = .requestFrame
    case .frame:
      let id = try payload.read(UInt64.self)
      let sequence = try payload.read(UInt64.self)
      let viewport = try payload.readSize()
      let count = Int(try payload.read(UInt32.self))
      guard count <= maximumCommandsPerFrame, count <= payload.readableBytes else {
        throw RemoteProtocolError.malformedMessage
      }
      var commands: [DrawCommand] = []
      commands.reserveCapacity(count)
      for _ in 0..<count { commands.append(try payload.readDrawCommand(images: &workingImages)) }
      message = .frame(id: id, inputSequence: sequence, viewport: viewport, commands: commands)
    }
    guard payload.readableBytes == 0 else { throw RemoteProtocolError.malformedMessage }
    images = workingImages
    return message
  }
}

extension ByteBuffer {
  fileprivate mutating func writeFloat(_ value: Float) {
    writeInteger(value.bitPattern, endianness: .little)
  }
  fileprivate mutating func writePoint(_ value: Point) {
    writeFloat(value.x)
    writeFloat(value.y)
  }
  fileprivate mutating func writeSize(_ value: Size) {
    writeFloat(value.width)
    writeFloat(value.height)
  }
  fileprivate mutating func writeRect(_ value: Rect) {
    writePoint(value.origin)
    writeSize(value.size)
  }
  fileprivate mutating func writeColor(_ value: Color) {
    writeFloat(value.r)
    writeFloat(value.g)
    writeFloat(value.b)
    writeFloat(value.a)
  }
  fileprivate mutating func writeRadii(_ value: CornerRadii) {
    writeFloat(value.topLeft)
    writeFloat(value.topRight)
    writeFloat(value.bottomRight)
    writeFloat(value.bottomLeft)
  }
  mutating func writeStringValue(_ value: String) throws {
    let bytes = value.utf8
    guard bytes.count <= Int(UInt32.max) else {
      throw RemoteProtocolError.stringTooLarge(bytes.count)
    }
    writeInteger(UInt32(bytes.count), endianness: .little)
    writeBytes(bytes)
  }

  fileprivate mutating func writeInput(_ input: InputState) throws {
    writePoint(input.pointerPosition)
    writePoint(input.pointerPressPosition)
    var flags: UInt8 = 0
    if input.pointerDown { flags |= 1 }
    if input.pointerPressed { flags |= 2 }
    if input.pointerReleased { flags |= 4 }
    writeInteger(flags)
    writePoint(input.scrollDelta)
    writeInteger(UInt32(input.commands.count), endianness: .little)
    for command in input.commands { try writeInputCommand(command) }
    writeInteger(UInt32(input.textEvents.count), endianness: .little)
    for event in input.textEvents { try writeTextEvent(event) }
  }

  fileprivate mutating func writeCommand(_ command: DrawCommand, images: inout RemoteImageCache) throws {
    switch command {
    case .fillRect(let rect, let color):
      writeInteger(UInt8(1))
      writeRect(rect)
      writeColor(color)
    case .strokeRect(let rect, let width, let color):
      writeInteger(UInt8(2))
      writeRect(rect)
      writeFloat(width)
      writeColor(color)
    case .fillRoundedRect(let rect, let radii, let color):
      writeInteger(UInt8(3))
      writeRect(rect)
      writeRadii(radii)
      writeColor(color)
    case .strokeRoundedRect(let rect, let radii, let width, let color):
      writeInteger(UInt8(4))
      writeRect(rect)
      writeRadii(radii)
      writeFloat(width)
      writeColor(color)
    case .text(let position, let text, let color, let scale):
      writeInteger(UInt8(5))
      writePoint(position)
      try writeStringValue(text)
      writeColor(color)
      writeFloat(scale)
    case .image(let rect, let image, let scaling, let alignment):
      if let cached = images.image(id: image.id), cached.generation == image.generation,
        cached.width == image.width, cached.height == image.height
      {
        writeInteger(UInt8(9))
        writeRect(rect)
        try writeStringValue(image.id.rawValue)
        writeInteger(image.generation, endianness: .little)
        writeInteger(scaling.wireValue)
        writeFloat(alignment.x)
        writeFloat(alignment.y)
        return
      }
      writeInteger(UInt8(6))
      writeRect(rect)
      try writeStringValue(image.id.rawValue)
      writeInteger(image.generation, endianness: .little)
      writeInteger(UInt32(image.width), endianness: .little)
      writeInteger(UInt32(image.height), endianness: .little)
      guard image.rgba8.count <= RemoteWire.maximumPayloadBytes else {
        throw RemoteProtocolError.imageTooLarge(image.rgba8.count)
      }
      writeInteger(UInt32(image.rgba8.count), endianness: .little)
      writeBytes(image.rgba8)
      images.insert(image)
      writeInteger(scaling.wireValue)
      writeFloat(alignment.x)
      writeFloat(alignment.y)
    case .pushClip(let rect):
      writeInteger(UInt8(7))
      writeRect(rect)
    case .popClip:
      writeInteger(UInt8(8))
    }
  }

  mutating func read<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
    guard let value: T = readInteger(endianness: .little) else {
      throw RemoteProtocolError.malformedMessage
    }
    return value
  }
  fileprivate mutating func readFloat() throws -> Float { Float(bitPattern: try read(UInt32.self)) }
  fileprivate mutating func readPoint() throws -> Point { Point(x: try readFloat(), y: try readFloat()) }
  fileprivate mutating func readSize() throws -> Size { Size(width: try readFloat(), height: try readFloat()) }
  fileprivate mutating func readRect() throws -> Rect { Rect(origin: try readPoint(), size: try readSize()) }
  fileprivate mutating func readColor() throws -> Color {
    Color(r: try readFloat(), g: try readFloat(), b: try readFloat(), a: try readFloat())
  }
  fileprivate mutating func readRadii() throws -> CornerRadii {
    CornerRadii(
      topLeft: try readFloat(), topRight: try readFloat(),
      bottomRight: try readFloat(), bottomLeft: try readFloat())
  }
  mutating func readStringValue() throws -> String {
    let length = Int(try read(UInt32.self))
    guard length <= RemoteWire.maximumPayloadBytes, let value = readString(length: length) else {
      throw RemoteProtocolError.malformedMessage
    }
    return value
  }

  fileprivate mutating func readInput() throws -> InputState {
    let position = try readPoint()
    let press = try readPoint()
    let flags = try read(UInt8.self)
    let scroll = try readPoint()
    let commandCount = Int(try read(UInt32.self))
    var commands: [Command] = []
    for _ in 0..<commandCount { commands.append(try readInputCommand()) }
    let textCount = Int(try read(UInt32.self))
    var text: [TextEditEvent] = []
    for _ in 0..<textCount { text.append(try readTextEvent()) }
    return InputState(
      pointerPosition: position, pointerPressPosition: press, pointerDown: flags & 1 != 0,
      pointerPressed: flags & 2 != 0, pointerReleased: flags & 4 != 0,
      scrollDelta: scroll, commands: commands, textEvents: text)
  }

  fileprivate mutating func readDrawCommand(images: inout RemoteImageCache) throws -> DrawCommand {
    switch try read(UInt8.self) {
    case 1: return .fillRect(rect: try readRect(), color: try readColor())
    case 2: return .strokeRect(rect: try readRect(), width: try readFloat(), color: try readColor())
    case 3: return .fillRoundedRect(rect: try readRect(), radii: try readRadii(), color: try readColor())
    case 4:
      return .strokeRoundedRect(
        rect: try readRect(), radii: try readRadii(), width: try readFloat(), color: try readColor())
    case 5:
      let point = try readPoint()
      let text = try readStringValue()
      let color = try readColor()
      let scale = try readFloat()
      return .text(position: point, text: text, color: color, scale: scale)
    case 9:
      let rect = try readRect()
      let id = ImageID(try readStringValue())
      let generation = try read(UInt64.self)
      guard let image = images.image(id: id), image.generation == generation,
        let scaling = ImageScaling(wireValue: try read(UInt8.self))
      else {
        throw RemoteProtocolError.malformedMessage
      }
      let alignment = ImageAlignment(x: try readFloat(), y: try readFloat())
      return .image(rect: rect, image: image, scaling: scaling, alignment: alignment)
    case 6:
      let rect = try readRect()
      let id = try readStringValue()
      let generation = try read(UInt64.self)
      let width = Int(try read(UInt32.self))
      let height = Int(try read(UInt32.self))
      let count = Int(try read(UInt32.self))
      guard count <= RemoteWire.maximumPayloadBytes, let rawBytes = readBytes(length: count) else {
        throw RemoteProtocolError.malformedMessage
      }
      let bytes = Data(rawBytes)
      let scalingByte = try read(UInt8.self)
      guard let scaling = ImageScaling(wireValue: scalingByte) else {
        throw RemoteProtocolError.malformedMessage
      }
      let alignment = ImageAlignment(x: try readFloat(), y: try readFloat())
      let image = try ImageResource(
        id: ImageID(id), generation: generation, width: width, height: height, rgba8: bytes)
      images.insert(image)
      return .image(rect: rect, image: image, scaling: scaling, alignment: alignment)
    case 7: return .pushClip(try readRect())
    case 8: return .popClip
    case let value: throw RemoteProtocolError.unknownCommand(value)
    }
  }
}

extension ImageScaling {
  fileprivate var wireValue: UInt8 {
    switch self {
    case .stretch: 0
    case .contain: 1
    case .cover: 2
    }
  }
  fileprivate init?(wireValue: UInt8) {
    switch wireValue {
    case 0: self = .stretch
    case 1: self = .contain
    case 2: self = .cover
    default: return nil
    }
  }
}

public struct RemoteKeyEvent: Codable, Equatable, Sendable {
  public var chord: KeyChord?
  public var text: String?
  public init(chord: KeyChord?, text: String? = nil) {
    self.chord = chord
    self.text = text
  }
}

public struct ClipboardTransfer: Codable, Equatable, Sendable {
  public var id: UInt64
  public var isReply: Bool
  public var text: String?
  public var success: Bool
  public init(id: UInt64, isReply: Bool = false, text: String? = nil, success: Bool = true) {
    self.id = id
    self.isReply = isReply
    self.text = text
    self.success = success
  }
}
