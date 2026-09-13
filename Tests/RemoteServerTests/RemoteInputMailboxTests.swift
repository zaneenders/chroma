import Foundation
import RemoteProtocol
import Testing

@testable import RemoteServer

@MainActor
struct RemoteInputMailboxTests {
  @Test func preservesOrderAcrossBatches() async throws {
    var received: [RemoteMessage] = []
    let mailbox = RemoteInputMailbox { received.append($0) }
    let messages = (1...100).map {
      RemoteMessage.key(sequence: UInt64($0), event: RemoteKeyEvent(chord: nil, text: "x"))
    }
    for message in messages { #expect(mailbox.enqueue(message, byteCount: 32)) }
    for _ in 0..<500 {
      if received.count == messages.count { break }
      try await Task.sleep(for: .milliseconds(2))
    }
    #expect(received == messages)
  }

  @Test func drainingReclaimsByteBudget() async throws {
    var delivered = 0
    let mailbox = RemoteInputMailbox { _ in delivered += 1 }
    for expected in 1...3 {
      #expect(mailbox.enqueue(.requestFrame, byteCount: RemoteInputMailbox.maximumBytes))
      for _ in 0..<500 {
        if delivered == expected { break }
        try await Task.sleep(for: .milliseconds(2))
      }
      #expect(delivered == expected)
    }
    mailbox.close()
  }

  @Test func countOverflowCancelsQueuedDelivery() async throws {
    var delivered = 0
    let mailbox = RemoteInputMailbox { _ in delivered += 1 }
    for _ in 0..<RemoteInputMailbox.maximumMessages {
      #expect(mailbox.enqueue(.requestFrame, byteCount: 16))
    }
    #expect(!mailbox.enqueue(.requestFrame, byteCount: 16))
    #expect(!mailbox.enqueue(.requestFrame, byteCount: 16))
    try await Task.sleep(for: .milliseconds(20))
    #expect(delivered == 0)
  }

  @Test func byteOverflowAndCloseCancelQueuedDelivery() async throws {
    var delivered = 0
    let mailbox = RemoteInputMailbox { _ in delivered += 1 }
    #expect(mailbox.enqueue(.requestFrame, byteCount: RemoteInputMailbox.maximumBytes))
    #expect(!mailbox.enqueue(.requestFrame, byteCount: 1))
    let closed = RemoteInputMailbox { _ in delivered += 1 }
    #expect(closed.enqueue(.requestFrame, byteCount: 16))
    closed.close()
    #expect(!closed.enqueue(.requestFrame, byteCount: 16))
    try await Task.sleep(for: .milliseconds(20))
    #expect(delivered == 0)
  }
}
