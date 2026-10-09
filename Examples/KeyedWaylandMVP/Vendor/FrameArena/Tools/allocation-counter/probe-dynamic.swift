import Glibc

typealias CounterGate = @convention(c) () -> Void
typealias CounterValue = @convention(c) (UInt32) -> UInt64

@inline(never)
func refill(_ values: inout UniqueArray<Int>, seed: Int) -> Int {
    values.removeAll()
    for i in 0..<1024 { values.append(i &+ seed) }
    var checksum = 0
    for i in 0..<values.count { checksum &+= values[i] }
    return checksum
}

@inline(never)
func positiveControl(start: CounterGate, stop: CounterGate) -> Int {
    start()
    var values = UniqueArray<Int>()
    values.reserveCapacity(1024)
    values.append(41)
    let result = values[0]
    stop()
    return result
}

func main() {
    guard let startSymbol = dlsym(nil, "allocation_counter_start"),
          let stopSymbol = dlsym(nil, "allocation_counter_stop"),
          let valueSymbol = dlsym(nil, "allocation_counter_value") else {
        print("Swift dlsym probe: counts unavailable (no preload)")
        return
    }
    let start = unsafeBitCast(startSymbol, to: CounterGate.self)
    let stop = unsafeBitCast(stopSymbol, to: CounterGate.self)
    let value = unsafeBitCast(valueSymbol, to: CounterValue.self)
    var values = UniqueArray<Int>()
    values.reserveCapacity(1024)
    var checksum = refill(&values, seed: 1)
    start()
    for frame in 0..<1000 { checksum &+= refill(&values, seed: frame) }
    stop()
    for index: UInt32 in 0..<6 { precondition(value(index) == 0) }
    print("Swift dlsym probe: all six counts zero; checksum=\(checksum)")
    let positive = positiveControl(start: start, stop: stop)
    let allocations = (0..<5).reduce(UInt64(0)) { $0 + value(UInt32($1)) }
    precondition(allocations > 0)
    print("Swift dlsym positive control: allocation calls=\(allocations); value=\(positive)")
}
main()
