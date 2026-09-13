import Foundation
import NIOCore

public struct DecodedRemoteMessage: Sendable {
  public let message: RemoteMessage
  public let byteCount: Int
  public let duration: TimeInterval
}

public struct RemoteMessageDecoder: ByteToMessageDecoder {
  public typealias InboundOut = DecodedRemoteMessage
  private var images = RemoteImageCache()

  public init() {}

  public mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
    let count = buffer.readableBytes
    let started = ProcessInfo.processInfo.systemUptime
    guard let message = try RemoteWire.decode(from: &buffer, images: &images) else { return .needMoreData }
    context.fireChannelRead(
      wrapInboundOut(
        DecodedRemoteMessage(
          message: message, byteCount: count - buffer.readableBytes,
          duration: ProcessInfo.processInfo.systemUptime - started)))
    return .continue
  }
}
