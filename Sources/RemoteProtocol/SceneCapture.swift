import Chroma
import Foundation
import NIOCore

public enum SceneCapture {
  public static let version = 1
  private static let magic: [UInt8] = Array("CHRCAP01".utf8)

  private struct Metadata: Codable {
    let version: Int
    let protocolVersion: UInt16
    let boundary: String
    let scaleX: Float?
    let scaleY: Float?
  }

  public static func encode(_ frame: FrameObservation) throws -> Data {
    let metadata = Metadata(
      version: version, protocolVersion: RemoteWire.version, boundary: "produced-pre-cull",
      scaleX: frame.rasterScale?.x, scaleY: frame.rasterScale?.y)
    let header = try JSONEncoder().encode(metadata)
    let wire = try RemoteWire.encode(
      .frame(id: 0, inputSequence: 0, viewport: frame.viewport, commands: frame.drawList.commands))
    var buffer = ByteBufferAllocator().buffer(capacity: 12 + header.count + wire.readableBytes)
    buffer.writeBytes(magic)
    buffer.writeInteger(UInt32(header.count), endianness: .little)
    buffer.writeBytes(header)
    buffer.writeBytes(wire.readableBytesView)
    return Data(buffer.readableBytesView)
  }

  public static func decode(_ data: Data) throws -> FrameObservation {
    guard data.count <= RemoteWire.maximumPayloadBytes + 65_536 else {
      throw RemoteProtocolError.messageTooLarge(data.count)
    }
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    guard buffer.readBytes(length: 8) == magic,
      let length = buffer.readInteger(endianness: .little, as: UInt32.self), length <= 16_384,
      let header = buffer.readBytes(length: Int(length))
    else {
      throw RemoteProtocolError.malformedMessage
    }
    let metadata = try JSONDecoder().decode(Metadata.self, from: Data(header))
    guard metadata.version == version, metadata.protocolVersion == RemoteWire.version,
      metadata.boundary == "produced-pre-cull"
    else {
      throw RemoteProtocolError.malformedMessage
    }
    let scale: Point?
    switch (metadata.scaleX, metadata.scaleY) {
    case (nil, nil): scale = nil
    case (.some(let x), .some(let y)) where x.isFinite && y.isFinite && x > 0 && y > 0:
      scale = Point(x: x, y: y)
    default: throw RemoteProtocolError.malformedMessage
    }
    guard
      case .frame(_, _, let viewport, let commands) = try RemoteWire.decode(
        from: &buffer), buffer.readableBytes == 0,
      viewport.width.isFinite, viewport.height.isFinite, viewport.width > 0, viewport.height > 0
    else {
      throw RemoteProtocolError.malformedMessage
    }
    return FrameObservation(drawList: DrawList(commands: commands), viewport: viewport, rasterScale: scale)
  }
}
