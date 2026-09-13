import NIOCore
import RemoteProtocol

enum ClipboardReplyEncoder {
  static func encode(_ reply: ClipboardTransfer) throws -> (bytes: ByteBuffer, notification: String?) {
    do {
      return (try RemoteWire.encode(.clipboard(reply)), nil)
    } catch RemoteProtocolError.messageTooLarge {
      let failure = ClipboardTransfer(id: reply.id, isReply: true, success: false)
      return (
        try RemoteWire.encode(.clipboard(failure)),
        "Paste failed: clipboard exceeds the 1 MiB transfer limit (including encoded metadata)."
      )
    }
  }
}
