#if os(Linux)
import Glibc

/// Optional Linux diagnostic interposer. No dependency or counter work in normal runs.
struct AllocationProbe {
    typealias Gate = @convention(c) () -> Void
    typealias Value = @convention(c) (UInt32) -> UInt64
    let start: Gate
    let stop: Gate
    let value: Value
    init?() {
        guard let a = dlsym(nil, "allocation_counter_start"), let b = dlsym(nil, "allocation_counter_stop"), let c = dlsym(nil, "allocation_counter_value") else { return nil }
        start = unsafeBitCast(a, to: Gate.self)
        stop = unsafeBitCast(b, to: Gate.self)
        value = unsafeBitCast(c, to: Value.self)
    }
    @inline(never)
    func positiveControl() {
        start()
        var storage = UniqueArray<Int>()
        storage.reserveCapacity(1024)
        storage.append(41)
        let result = storage[0]
        stop()
        precondition(result == 41 && (0..<5).reduce(UInt64(0), { $0 + value(UInt32($1)) }) > 0, "Allocation interposer is not connected")
    }
    func printCounts() {
        print("malloc=\(value(0)) calloc=\(value(1)) realloc=\(value(2)) aligned_alloc=\(value(3)) posix_memalign=\(value(4)) free=\(value(5))")
    }
}
#else
struct AllocationProbe {
    init?() { return nil }
    func start() {}
    func stop() {}
    func positiveControl() {}
    func printCounts() {}
}
#endif

#if os(Linux)
func processCPUSeconds() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &time)
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
}
#else
import Foundation
func processCPUSeconds() -> Double { .nan }
#endif
