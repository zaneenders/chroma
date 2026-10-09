import Testing
@testable import FrameArena

final class Destructions {
    var payloads = 0
    var references = 0
    var captures = 0
}

final class ReferenceProbe {
    let counts: Destructions
    let isCapture: Bool
    init(_ counts: Destructions, capture: Bool = false) {
        self.counts = counts
        self.isCapture = capture
    }
    deinit {
        if isCapture { counts.captures += 1 } else { counts.references += 1 }
    }
}

struct OwnedPayload: ~Copyable {
    let text: String
    let reference: ReferenceProbe
    let action: () -> Int
    let counts: Destructions

    init(_ counts: Destructions, value: Int) {
        self.counts = counts
        text = String(repeating: "payload-\(value)-", count: 32)
        reference = ReferenceProbe(counts)
        let capture = ReferenceProbe(counts, capture: true)
        action = { [capture] in capture.isCapture ? value : -1 }
    }
    deinit { counts.payloads += 1 }
}

@Test func emptyGrowthAndReuse() {
    var arena = FrameArena<Int>()
    #expect(arena.count == 0)
    #expect(arena.view.count == 0)
    arena.reset()
    arena.reserveCapacity(128)
    let capacity = arena.capacity
    for n in 0..<128 { arena.append(n) }
    #expect(arena.capacity == capacity)
    #expect(arena.view[127] == 127)
    let address = arena.view.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
    arena.reset()
    #expect(arena.count == 0)
    #expect(arena.capacity == capacity)
    for n in 0..<128 { arena.append(n * 2) }
    #expect(arena.view.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) } == address)
    #expect(arena.view[127] == 254)
    let beforeGrowth = arena.append(998)
    let h = arena.append(999)
    #expect(arena.capacity > capacity)
    #expect(arena.view[arena.index(of: h)!] == 999)
    #expect(arena.view[arena.index(of: beforeGrowth)!] == 998)
}

@Test func handlesRejectResetForeignOwnerAndOwnerReuse() {
    var arena = FrameArena<Int>()
    let first = arena.append(10)
    #expect(arena.index(of: first) == 0)
    let replaced = arena.replace(first, with: 11)
    #expect(replaced)
    #expect(arena.view[0] == 11)
    var other = FrameArena<Int>()
    other.append(20)
    #expect(other.index(of: first) == nil)
    let rejectedForeign = other.replace(first, with: 30)
    #expect(!rejectedForeign)
    arena.reset()
    arena.append(40)
    #expect(arena.index(of: first) == nil)
    let rejectedStale = arena.replace(first, with: 50)
    #expect(!rejectedStale)
    let deadOwnerHandle = makeDeadOwnerHandle()
    for _ in 0..<256 {
        var next = FrameArena<Int>()
        next.append(60)
        #expect(next.index(of: deadOwnerHandle) == nil)
    }
}

private func makeDeadOwnerHandle() -> FrameHandle<Int> {
    var arena = FrameArena<Int>()
    return arena.append(1)
}

@Test func resetAndOwnerDestructionReleaseNontrivialPayloads() {
    let counts = Destructions()
    fillResetAndDestroy(counts)
    #expect(counts.payloads == 9)
    #expect(counts.references == 9)
    #expect(counts.captures == 9)
}

private func fillResetAndDestroy(_ counts: Destructions) {
    var arena = FrameArena<OwnedPayload>(reserving: 8)
    for i in 0..<4 { arena.append(OwnedPayload(counts, value: i)) }
    #expect(arena.view[3].action() == 3)
    #expect(arena.view[0].text.count > 15)
    #expect(counts.payloads == 0)
    arena.reset()
    #expect(counts.payloads == 4)
    #expect(counts.references == 4)
    #expect(counts.captures == 4)
    let capacity = arena.capacity
    arena.reset() // Empty reset cannot double-destroy.
    #expect(counts.payloads == 4)
    for i in 0..<5 { arena.append(OwnedPayload(counts, value: i)) }
    #expect(arena.capacity == capacity)
    // Remaining five payloads, including their Strings, die with the owner.
}

@Test func replacementAndRejectedReplacementDestroyTheirInputs() {
    let counts = Destructions()
    var arena = FrameArena<OwnedPayload>()
    let first = arena.append(OwnedPayload(counts, value: 1))
    let replaced = arena.replace(first, with: OwnedPayload(counts, value: 2))
    #expect(replaced)
    #expect(counts.payloads == 1)
    arena.reset()
    #expect(counts.payloads == 2)
    let rejected = arena.replace(first, with: OwnedPayload(counts, value: 3))
    #expect(!rejected)
    #expect(counts.payloads == 3)
    #expect(counts.references == 3)
    #expect(counts.captures == 3)
}

@Test func slabEmptyCapacityAndOverflowRejection() {
    var empty = TrivialSlab<Int>(capacity: 0)
    #expect(empty.view.count == 0)
    #expect(empty.append(1) == nil)
    empty.reset()
    var slab = TrivialSlab<Int>(capacity: 2)
    let first = slab.append(10)!
    #expect(slab.append(20) != nil)
    #expect(slab.append(30) == nil)
    #expect(slab.count == 2)
    #expect(slab.view[1] == 20)
    #expect(slab.index(of: first) == 0)
    slab.reset()
    #expect(slab.count == 0)
    #expect(slab.index(of: first) == nil)
    #expect(slab.append(40) != nil)
    #expect(slab.view[0] == 40)
    var other = TrivialSlab<Int>(capacity: 2)
    _ = other.append(50)
    #expect(other.index(of: first) == nil)
}

struct AlignedRecord: BitwiseCopyable {
    var vector: SIMD4<Double>
    var key: UInt64
}

@Test func slabPreservesAlignmentAndWarmAddress() {
    var slab = TrivialSlab<AlignedRecord>(capacity: 256)
    var address: UInt = 0
    for frame in 0..<16 {
        for i in 0..<256 {
            #expect(slab.append(AlignedRecord(vector: .init(repeating: Double(i)), key: UInt64(i))) != nil)
        }
        let current = slab.view.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
        #expect(current % UInt(MemoryLayout<AlignedRecord>.alignment) == 0)
        if frame == 0 { address = current } else { #expect(current == address) }
        #expect(slab.view[255].vector[3] == 255)
        slab.reset()
    }
}

@Test func owningSnapshotSurvivesReset() {
    var arena = FrameArena<Int>(reserving: 4)
    arena.append(42)
    // Explicit owned copy for asynchronous consumers; never pass a Span to a GPU.
    let snapshot = arena.view.withUnsafeBufferPointer { Array($0) }
    arena.reset()
    arena.append(99)
    #expect(snapshot == [42])
    #expect(arena.view[0] == 99)
}
