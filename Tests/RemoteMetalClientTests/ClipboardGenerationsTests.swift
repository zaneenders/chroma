import Testing

@testable import RemoteMetalClient

@Suite("Remote clipboard gesture ordering")
struct ClipboardGenerationsTests {
  @Test func queuedPasteFollowsCopyWrite() {
    var generations = ClipboardGenerations()
    generations.record(sequence: 1, generation: 10)
    generations.record(sequence: 2, generation: 10)

    #expect(generations.consume(sequence: 1) == 10)
    generations.didWrite(sequence: 1, from: 10, to: 12)
    #expect(generations.consume(sequence: 2) == 12)
    #expect(generations.consume(sequence: 2) == nil)
  }

  @Test func queuedWritesAdvanceTransitively() {
    var generations = ClipboardGenerations()
    for sequence: UInt64 in 1...3 {
      generations.record(sequence: sequence, generation: 10)
    }
    #expect(generations.consume(sequence: 1) == 10)
    generations.didWrite(sequence: 1, from: 10, to: 12)
    #expect(generations.consume(sequence: 2) == 12)
    generations.didWrite(sequence: 2, from: 12, to: 14)
    #expect(generations.consume(sequence: 3) == 14)
  }

  @Test func externalChangesStillInvalidateGestures() {
    var generations = ClipboardGenerations()
    generations.record(sequence: 1, generation: 10)
    generations.record(sequence: 2, generation: 10)
    generations.record(sequence: 3, generation: 11)
    #expect(generations.consume(sequence: 1) != 11)
    #expect(generations.consume(sequence: 2) != 11)
    #expect(generations.consume(sequence: 3) == 11)
  }

  @Test func ownWriteDoesNotReviveStaleGestures() {
    var generations = ClipboardGenerations()
    generations.record(sequence: 1, generation: 10)
    generations.record(sequence: 2, generation: 11)
    generations.record(sequence: 3, generation: 10)
    generations.record(sequence: 4, generation: 11)
    #expect(generations.consume(sequence: 2) == 11)
    generations.didWrite(sequence: 2, from: 11, to: 13)
    #expect(generations.consume(sequence: 1) == 10)
    #expect(generations.consume(sequence: 3) == 10)
    #expect(generations.consume(sequence: 4) == 13)
  }

  @Test func metadataIsBoundedAndClearedOnDisconnect() {
    var generations = ClipboardGenerations()
    generations.record(sequence: 1, generation: 10)
    generations.record(sequence: 1025, generation: 10)
    #expect(generations.consume(sequence: 1) == nil)
    generations.removeAll()
    #expect(generations.consume(sequence: 1025) == nil)
  }
}
