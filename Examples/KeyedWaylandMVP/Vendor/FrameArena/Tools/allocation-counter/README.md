# Linux/glibc allocation-call counter

This isolated harness counts outermost intercepted `malloc`, `calloc`, `realloc`,
`aligned_alloc`, `posix_memalign`, and `free` calls in an explicitly gated region
on the calling thread. It is for allocation diagnostics, not timing runs.

## Verified invocation

```sh
bash Tools/allocation-counter/verify.sh
```

The script uses `swiftc` from PATH. Override `SWIFTC` to select a compatible
Swift 6.4 compiler. Its module cache is under the local `build` directory.

Verified on Linux x86_64, glibc, GCC 14.2, and Swift 6.4:

```text
C routes: malloc=1 calloc=1 realloc=1 aligned_alloc=1 posix_memalign=1 free=4
C gate/reset/thread-isolation checks passed
Swift prewarmed UniqueArray<Int>: malloc=0 calloc=0 realloc=0 aligned_alloc=0 posix_memalign=0 free=0; checksum=1035788800
Swift positive control: malloc=0 calloc=0 realloc=0 aligned_alloc=0 posix_memalign=1 free=0; value=41
Swift dlsym probe: counts unavailable (no preload)
Swift dlsym probe: all six counts zero; checksum=1035788800
Swift dlsym positive control: allocation calls=1; value=41
```

The Swift zero-allocation check reserves 1,024 `Int` slots, performs one warm-up
refill, and then measures 1,000 clear/refill/read cycles. A non-inlined function
and consumed checksum retain observable work. In Swift 6.4, `UniqueArray.removeAll()`
has no `keepingCapacity` parameter and retains the existing capacity. The
positive control reserves fresh storage inside the gate to ensure the counter
is connected. The C probe is built with `-fno-builtin` so GCC does not elide or
substitute the explicit allocation calls.

## Use with another Swift executable

From the prototype directory, after `verify.sh` has built the shared library:

```sh
COUNTER="$PWD/Tools/allocation-counter"
SWIFTC=/workspace/shared/swift-setup/toolchains/6.4.0/usr/bin/swiftc
"$SWIFTC" -O -module-cache-path /tmp/swift-frame-arena-module-cache \
  -I "$COUNTER" -L "$COUNTER/build" -lallocation_counter \
  -Xlinker -rpath -Xlinker "$COUNTER/build" \
  your-benchmark.swift -o your-benchmark
LD_PRELOAD="$COUNTER/build/liballocation_counter.so" ./your-benchmark
```

Gate the loop in Swift, after setup and warm-up:

```swift
import AllocationCounter

// Reserve storage and run an identical warm-up before starting.
allocation_counter_start() // Resets this thread's counters and enables them.
// Run the actual benchmark loop here. Avoid printing or formatting strings.
allocation_counter_stop()
let c = allocation_counter_read()
print("malloc=\(c.malloc_calls), calloc=\(c.calloc_calls), realloc=\(c.realloc_calls)")
print("aligned_alloc=\(c.aligned_alloc_calls), posix_memalign=\(c.posix_memalign_calls), free=\(c.free_calls)")
```

The same header/module map can be supplied to an existing Swift build using its
compiler include-path and linker search-path options; no Swift package files
are modified by this harness. Linking the library makes the gate functions
available, while `LD_PRELOAD` puts its allocator wrappers first in symbol lookup.
Use an absolute preload path. Run a fresh-allocation positive control whenever
changing the compiler, linking arrangement, or benchmark executable.

## Optional runtime lookup, with no link-time dependency

`probe-dynamic.swift` demonstrates a Swift executable that uses only `Glibc` and
does not link this library. This is suitable for a SwiftPM benchmark that runs
normally for timing, then runs separately under the optional preload for counts.
Resolve all three symbols once, before warm-up or measurement:

```swift
import Glibc
typealias CounterGate = @convention(c) () -> Void
typealias CounterValue = @convention(c) (UInt32) -> UInt64

guard let startSymbol = dlsym(nil, "allocation_counter_start"),
      let stopSymbol = dlsym(nil, "allocation_counter_stop"),
      let valueSymbol = dlsym(nil, "allocation_counter_value") else {
    // No preload: report allocation counts unavailable and still run timing.
    return
}
let start = unsafeBitCast(startSymbol, to: CounterGate.self)
let stop = unsafeBitCast(stopSymbol, to: CounterGate.self)
let value = unsafeBitCast(valueSymbol, to: CounterValue.self)
// Reserve and prewarm here.
start()
// Measured loop here.
stop()
let mallocCalls = value(0)
let posixMemalignCalls = value(4)
```

Indices are `0=malloc`, `1=calloc`, `2=realloc`, `3=aligned_alloc`,
`4=posix_memalign`, `5=free`. An invalid index returns zero. On this Linux target,
the C `unsigned` argument is `UInt32` and the `uint64_t` result is `UInt64`.
The original struct-returning `allocation_counter_read()` remains available.
The dynamic probe is tested both without and with `LD_PRELOAD` by `verify.sh`.

## Implementation and limits

- Counts are calls, including failed attempts, zero-size requests, and
  `free(NULL)`. They are not allocation bytes, live-object counts, retained
  bytes, peak memory, syscall counts, a leak detector, or an exhaustive heap
  census. A `realloc` is one call even if it moves storage internally.
- Counters and the enable/depth flags use static, initial-exec thread-local
  storage. A region observes only its calling OS thread. Other threads do not
  contribute, and a newly spawned thread is disabled until it starts its own
  region. There is no aggregation. Do not use this as a task-wide Swift
  concurrency counter: a task can migrate between OS threads.
- Regions are not nestable; `start` always resets. Stop before reading results
  and before printing them. Gate functions and wrappers perform no logging or
  dynamic memory allocation of their own. Counter overflow is not checked.
- `malloc`, `calloc`, `realloc`, and `free` forward directly to glibc's exported
  `__libc_*` entry points, avoiding recursive symbol lookup. A per-thread depth
  guard suppresses any nested wrapper calls made by another intercepted
  allocator implementation, so the columns are outermost entry-point counts.
- `aligned_alloc` and `posix_memalign` forward to their actual `RTLD_NEXT`
  implementations, resolved in the library constructor before normal program
  execution. Early loader calls before resolution use a glibc `__libc_memalign`
  fallback with alignment/error handling. If symbol resolution fails, startup
  exits with status 127. This is an intentional glibc-only diagnostic shim,
  not a portable replacement allocator.
- Load at process startup with `LD_PRELOAD`; do not dynamically load/unload it
  after threads start. Do not combine it with alternate allocators, allocator
  preloads, malloc-debug libraries, or sanitizers. Those can change symbol
  routing and invalidate both semantics and counts.
- It cannot observe calls bypassing these public interposed symbols: direct
  `__libc_*` or hidden/internal allocator calls, non-interposable/static-linked
  code, private heaps, direct `mmap`/`brk`, stack allocations, or independent
  `memalign`, `valloc`, `pvalloc`, and `reallocarray` routes. Such routes count
  only if they happen to reach one of the intercepted symbols. Optimizer-elided
  allocations naturally produce no calls.
- This is not async-signal-safe instrumentation. Do not use gate functions in
  signal handlers or use the harness to study signal-handler allocation.
- The wrappers add overhead. Measure timing in a separate run without this
  preload; report these results specifically as intercepted allocation calls
  for the warmed loop, rather than a blanket claim of zero heap allocation.

All sources, probes, and generated binaries remain under this directory; the
only external generated content is the explicitly selected `/tmp` module cache.
