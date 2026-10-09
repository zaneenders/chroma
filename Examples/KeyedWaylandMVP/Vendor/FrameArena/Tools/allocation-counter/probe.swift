import AllocationCounter
import Glibc

@inline(never)
func refill(_ values: inout UniqueArray<Int>, count: Int, seed: Int) -> Int {
    values.removeAll()
    for i in 0..<count { values.append(i &+ seed) }
    var checksum = 0
    for i in 0..<values.count { checksum &+= values[i] }
    return checksum
}

func total(_ c: allocation_counts) -> UInt64 {
    c.malloc_calls + c.calloc_calls + c.realloc_calls
        + c.aligned_alloc_calls + c.posix_memalign_calls
}

func describe(_ c: allocation_counts) -> String {
    "malloc=\(c.malloc_calls) calloc=\(c.calloc_calls) realloc=\(c.realloc_calls) "
        + "aligned_alloc=\(c.aligned_alloc_calls) posix_memalign=\(c.posix_memalign_calls) free=\(c.free_calls)"
}

// Compile separately at -O. The positive control catches a disconnected counter.
@inline(never)
func positiveControl() -> (Int, allocation_counts) {
    allocation_counter_start()
    var values = UniqueArray<Int>()
    values.reserveCapacity(1024)
    values.append(41)
    let result = values[0]
    allocation_counter_stop()
    let counts = allocation_counter_read()
    return (result, counts)
}

func main() {
    // Force Swift runtime and formatting setup outside the measured region.
    var values = UniqueArray<Int>()
    values.reserveCapacity(1024)
    var checksum = refill(&values, count: 1024, seed: 1)
    _ = describe(allocation_counter_read())
    allocation_counter_start()
    for frame in 0..<1000 {
        checksum &+= refill(&values, count: 1024, seed: frame)
    }
    allocation_counter_stop()
    let measured = allocation_counter_read()
    print("Swift prewarmed UniqueArray<Int>: \(describe(measured)); checksum=\(checksum)")
    precondition(total(measured) == 0, "reserved primitive hot loop allocated")
    let positive = positiveControl()
    print("Swift positive control: \(describe(positive.1)); value=\(positive.0)")
    precondition(total(positive.1) > 0, "positive control must allocate")
}
main()
