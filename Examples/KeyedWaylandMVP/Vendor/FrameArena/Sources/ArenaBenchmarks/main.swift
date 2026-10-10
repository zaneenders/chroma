#if !ARENA_STANDALONE
import FrameArena
#endif
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import Foundation

struct DrawRecord: BitwiseCopyable {
    var key: UInt64
    var x: Float
    var y: Float
    var width: Float
    var height: Float
    var color: UInt32
    var kind: UInt32
}

@inline(__always)
func record(_ index: Int, _ frame: Int) -> DrawRecord {
    DrawRecord(key: UInt64(index ^ frame), x: Float(index & 255), y: Float(frame & 127),
               width: Float((index & 31) + 1), height: 20,
               color: UInt32(truncatingIfNeeded: index &* 1664525 &+ frame), kind: UInt32(index & 3))
}

// Every stored field affects an observable checksum; no opaque pointer escapes.
@inline(never)
func consumeRecords(_ records: Span<DrawRecord>) -> UInt64 {
    var sum: UInt64 = 0
    for i in 0..<records.count {
        let r = records[i]
        sum &+= r.key &+ UInt64(r.x.bitPattern) &+ UInt64(r.y.bitPattern)
            &+ UInt64(r.width.bitPattern) &+ UInt64(r.height.bitPattern)
            &+ UInt64(r.color) &+ UInt64(r.kind)
    }
    return sum
}

@inline(never)
func refillArray(_ a: inout [DrawRecord], _ n: Int, _ frame: Int) -> UInt64 {
    a.removeAll(keepingCapacity: true)
    for i in 0..<n { a.append(record(i, frame)) }
    return consumeRecords(a.span)
}
@inline(never)
func refillUnique(_ a: inout UniqueArray<DrawRecord>, _ n: Int, _ frame: Int) -> UInt64 {
    a.removeAll()
    for i in 0..<n { a.append(record(i, frame)) }
    return consumeRecords(a.span)
}
@inline(never)
func refillArena(_ a: inout FrameArena<DrawRecord>, _ n: Int, _ frame: Int) -> UInt64 {
    a.reset()
    for i in 0..<n { a.append(record(i, frame)) }
    return consumeRecords(a.view)
}
@inline(never)
func refillSlab(_ a: inout TrivialSlab<DrawRecord>, _ n: Int, _ frame: Int) -> UInt64 {
    a.reset()
    for i in 0..<n { precondition(a.append(record(i, frame)) != nil) }
    return consumeRecords(a.view)
}

struct Counter {
    typealias Gate = @convention(c) () -> Void
    typealias Read = @convention(c) (UInt32) -> UInt64
    var start: Gate?
    var stop: Gate?
    var read: Read?
    init() {
        #if os(Linux)
        if let handle = dlopen(nil, RTLD_NOW),
           let a = dlsym(handle, "allocation_counter_start"),
           let b = dlsym(handle, "allocation_counter_stop"),
           let c = dlsym(handle, "allocation_counter_value") {
            start = unsafeBitCast(a, to: Gate.self)
            stop = unsafeBitCast(b, to: Gate.self)
            read = unsafeBitCast(c, to: Read.self)
        }
        #endif
    }
}
let counter = Counter()

func now(_ clock: clockid_t) -> UInt64 {
    var time = timespec()
    precondition(clock_gettime(clock, &time) == 0)
    return UInt64(time.tv_sec) * 1_000_000_000 + UInt64(time.tv_nsec)
}

struct Measurement {
    let cpu: UInt64
    let wall: UInt64
    let checksum: UInt64
    let calls: [UInt64]?
}
func measure(_ body: () -> UInt64) -> Measurement {
    let cpu = now(CLOCK_PROCESS_CPUTIME_ID)
    let wall = now(CLOCK_MONOTONIC)
    counter.start?()
    let checksum = body()
    counter.stop?()
    let elapsedWall = now(CLOCK_MONOTONIC) - wall
    let elapsedCPU = now(CLOCK_PROCESS_CPUTIME_ID) - cpu
    let calls = counter.read.map { read in (0..<6).map { read(UInt32($0)) } }
    return Measurement(cpu: elapsedCPU, wall: elapsedWall, checksum: checksum, calls: calls)
}

enum Storage: String, CaseIterable { case array, unique, arena, slab }
enum Phase: String, CaseIterable { case warm, coldReserved, coldGrowing }

func trial(_ storage: Storage, _ phase: Phase, _ n: Int, _ frames: Int) -> Measurement {
    switch storage {
    case .array:
        var a = [DrawRecord]()
        if phase == .warm { a.reserveCapacity(n); _ = refillArray(&a, n, 0) }
        return measure {
            var sum: UInt64 = 0
            for f in 0..<frames {
                if phase != .warm { a = []; if phase == .coldReserved { a.reserveCapacity(n) } }
                sum &+= refillArray(&a, n, f)
            }
            a.removeAll(keepingCapacity: true)
            return sum
        }
    case .unique:
        var a = UniqueArray<DrawRecord>()
        if phase == .warm { a.reserveCapacity(n); _ = refillUnique(&a, n, 0) }
        return measure {
            var sum: UInt64 = 0
            for f in 0..<frames {
                if phase != .warm { a = UniqueArray(); if phase == .coldReserved { a.reserveCapacity(n) } }
                sum &+= refillUnique(&a, n, f)
            }
            a.removeAll()
            return sum
        }
    case .arena:
        var a = FrameArena<DrawRecord>()
        if phase == .warm { a.reserveCapacity(n); _ = refillArena(&a, n, 0) }
        return measure {
            var sum: UInt64 = 0
            for f in 0..<frames {
                if phase != .warm { a = FrameArena(); if phase == .coldReserved { a.reserveCapacity(n) } }
                sum &+= refillArena(&a, n, f)
            }
            a.reset()
            return sum
        }
    case .slab:
        var a = TrivialSlab<DrawRecord>(capacity: phase == .warm ? n : 0)
        if phase == .warm { _ = refillSlab(&a, n, 0) }
        return measure {
            var sum: UInt64 = 0
            for f in 0..<frames {
                if phase != .warm { a = TrivialSlab(capacity: 0); a = TrivialSlab(capacity: n) }
                sum &+= refillSlab(&a, n, f)
            }
            a.reset()
            return sum
        }
    }
}

// Count backing-capacity changes separately from measured malloc-family calls.
func capacityChanges(_ storage: Storage, _ reserved: Bool, _ n: Int) -> Int {
    switch storage {
    case .array:
        var a = [DrawRecord](); var changes = 0
        if reserved { a.reserveCapacity(n); changes += 1 }
        for i in 0..<n { let c = a.capacity; a.append(record(i, 0)); if a.capacity != c { changes += 1 } }
        return changes
    case .unique:
        var a = UniqueArray<DrawRecord>(); var changes = 0
        if reserved { a.reserveCapacity(n); changes += 1 }
        for i in 0..<n { let c = a.capacity; a.append(record(i, 0)); if a.capacity != c { changes += 1 } }
        return changes
    case .arena:
        var a = FrameArena<DrawRecord>(); var changes = 0
        if reserved { a.reserveCapacity(n); changes += 1 }
        for i in 0..<n { let c = a.capacity; a.append(record(i, 0)); if a.capacity != c { changes += 1 } }
        return changes
    case .slab: return 1
    }
}

final class Box { let value: Int; init(_ value: Int) { self.value = value } }
struct Payload { let text: String; let ref: Box; let action: () -> Int }
@inline(never)
func payload(_ i: Int) -> Payload {
    let capture = Box(i)
    return Payload(text: String(repeating: "frame-\(i)-", count: 16), ref: Box(i), action: { capture.value })
}
@inline(never)
func consumePayloads(_ values: Span<Payload>) -> UInt64 {
    var sum: UInt64 = 0
    for i in 0..<values.count { sum &+= UInt64(values[i].text.count + values[i].ref.value + values[i].action()) }
    return sum
}
func payloadTrial(_ useArena: Bool, _ n: Int, _ frames: Int) -> Measurement {
    if useArena {
        var a = FrameArena<Payload>(reserving: n)
        a.append(payload(1)); a.reset()
        return measure {
            var sum: UInt64 = 0
            for f in 0..<frames {
                a.reset()
                for i in 0..<n { a.append(payload(i + f)) }
                sum &+= consumePayloads(a.view)
            }
            a.reset()
            return sum
        }
    }
    var a = UniqueArray<Payload>(); a.reserveCapacity(n)
    a.append(payload(1)); a.removeAll()
    return measure {
        var sum: UInt64 = 0
        for f in 0..<frames {
            a.removeAll()
            for i in 0..<n { a.append(payload(i + f)) }
            sum &+= consumePayloads(a.span)
        }
        a.removeAll()
        return sum
    }
}

let allocations = CommandLine.arguments.contains("--allocations")
precondition(!allocations || counter.start != nil, "--allocations needs the verified Linux preload counter")
precondition(allocations || counter.start == nil, "Timing run must not preload the allocation counter")
let n = Int(ProcessInfo.processInfo.environment["ARENA_RECORDS"] ?? "4096")!
let frames = Int(ProcessInfo.processInfo.environment["ARENA_FRAMES"] ?? "1024")!
let samples = Int(ProcessInfo.processInfo.environment["ARENA_SAMPLES"] ?? "9")!
precondition(n > 0 && frames > 0 && samples > 0)
print("kind,storage,phase,sample,records_per_frame,frames,record_stride,cpu_ns,wall_ns,checksum,capacity_changes,malloc,calloc,realloc,aligned_alloc,posix_memalign,free")
func emit(_ storage: String, _ phase: String, _ sample: Int, _ count: Int, _ frames: Int, _ stride: Int, _ result: Measurement, _ growth: Int) {
    let calls = result.calls?.map(String.init).joined(separator: ",") ?? "NA,NA,NA,NA,NA,NA"
    print("\(allocations ? "allocations" : "timing"),\(storage),\(phase),\(sample),\(count),\(frames),\(stride),\(result.cpu),\(result.wall),\(result.checksum),\(growth),\(calls)")
}
// Rotate variant order per sample to reduce drift bias; require identical checksums.
var checksums = [String: UInt64]()
for sample in 0..<samples {
    for phase in Phase.allCases {
        let order = Array(Storage.allCases.dropFirst(sample % 4)) + Array(Storage.allCases.prefix(sample % 4))
        for storage in order {
            if storage == .slab && phase == .coldGrowing { continue }
            let result = trial(storage, phase, n, frames)
            if let expected = checksums["records"] { precondition(result.checksum == expected) }
            checksums["records"] = result.checksum
            let growth = phase == .warm ? 0 : frames * capacityChanges(storage, phase == .coldReserved, n)
            emit(storage.rawValue, phase.rawValue, sample, n, frames, MemoryLayout<DrawRecord>.stride, result, growth)
        }
    }
    for useArena in (sample % 2 == 0 ? [false, true] : [true, false]) {
        let result = payloadTrial(useArena, 256, 128)
        if let expected = checksums["payloads"] { precondition(result.checksum == expected) }
        checksums["payloads"] = result.checksum
        emit(useArena ? "arena" : "unique", "warmPayload", sample, 256, 128, MemoryLayout<Payload>.stride, result, 0)
    }
}
