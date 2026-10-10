# Swift frame storage prototype

Two small alternatives, isolated from the production renderer:

- **FrameArena** is a typed `UniqueArray` wrapper, not a new allocator. It adds
  checked frame handles, one noncopyable owner, and a nonescaping borrowed view.
  It grows as needed and retains high-water capacity across resets.
- **TrivialSlab** is an actual fixed-capacity allocation policy. It allocates one
  aligned typed block up front, advances an initialized prefix, and refuses an
  append when full. It never grows or silently spills. `BitwiseCopyable` excludes
  String, owning references and capturing closures.

The implementation is 132 lines including comments and shared handle/identity
support: 80 in FrameArena.swift, 52 in TrivialSlab.swift. Tests and measurement
infrastructure are deliberately separate from these two files.

## Run

Requires Swift 6.4. The package enables the experimental `Lifetimes` feature.
Tested on Linux x86_64; Apple deployment is set to macOS 27 because this toolchain's
standard-library `UniqueArray` has that availability. No Apple build is claimed.
No package dependencies are downloaded.

```sh
swift test
SWIFTC=swiftc bash Tools/compile-fail.sh
SWIFTC=swiftc bash Tools/trap-tests.sh
SWIFTC=swiftc bash Tools/benchmark.sh
```

For a read-only home directory, set `SWIFTPM_MODULECACHE_OVERRIDE` and
`CLANG_MODULE_CACHE_PATH` to a writable directory before `swift test`.
The standalone tool scripts keep build outputs under `.build` or their own
`build` directory. Allocation interception additionally requires Linux/glibc and
GCC. Timing works without the interceptor. On other platforms only timing is run.

## Minimal use

```swift
import FrameArena

var records = FrameArena<Int>(reserving: 1024)
let first = records.append(42)
// Build recursively using handles; resolve only against their original owner.
if let index = records.index(of: first) {
    print(records.view[index]) // Short, immutable borrow.
}
records.reset()                // Releases payload ownership; retains capacity.
assert(records.index(of: first) == nil)

var bounded = TrivialSlab<SIMD4<Float>>(capacity: 1024)
guard bounded.append(SIMD4(repeating: 1)) != nil else {
    fatalError("Frame command budget exceeded")
}
print(bounded.view[0])
bounded.reset()
```

The compiler rejects using `view` after reset, append, replacement or reserve;
returning it from a dead local owner; storing it in an escapable value; and copying
either owner. A Span is a borrow, not an owned snapshot. Lifetime annotations
borrow existing storage; they do not move Strings or closure environments into
that storage or eliminate ARC within elements.

Handles are ordinary escapable values with a process-unique owner ID, checked
nonwrapping generation and index. They do not retain the arena. `index(of:)` must
succeed before indexing. A reset invalidates previous handles even when addresses
and indices are reused. Mutation is exclusive; neither type is a synchronized
shared collection.

## Safety boundary

The typed wrapper delegates initialization, element destruction, capacity growth
and alignment to `UniqueArray`. It supports noncopyable elements too. `reset()`
destroys initialized elements immediately, but an independently owned copy of a
String, object or closure can naturally keep its underlying storage alive.

The slab's unsafe boundary is only 52 lines: typed allocation supplies alignment;
checked stride multiplication prevents byte-count overflow; `count < capacity`
precedes pointer arithmetic; exactly the initialized prefix is deinitialized;
and the pointer is deallocated once. Its Span uses `_overrideLifetime` to bind the
unsafe buffer to a borrow of its owner. That annotation relies on these internal
invariants; it is not a proof that arbitrary unsafe pointer code is safe.

Empty capacity is valid and allocation-free. Capacity exhaustion returns nil;
invalid negative capacities, arithmetic overflow and out-of-bounds reads trap.
Do not compile with unchecked optimization if those checks are required.

Synchronous layout/drawing may borrow. An asynchronous GPU, compositor buffer,
returned DrawList, or historical snapshot needs separate owning storage whose
lifetime reaches completion/release. The snapshot test demonstrates an explicit
Array copy surviving reset. No GPU integration or asynchronous-buffer safety is
claimed by this package. Persistent keyed UI state also belongs outside this
per-frame allocator; keys are not frame handles.

## Verification

- 7 runtime tests: empty/growth/reuse, stable warm addresses, foreign/stale/dead
  owner handles, replacement, aligned SIMD records, exact payload/reference/
  closure-capture destruction, and a retained owning snapshot.
- 12 compile-fail tests, plus a positive control: both owners cannot be copied,
  views cannot outlive owners or coexist with mutation, escapable storage cannot
  hold a Span, and the slab rejects Strings and closures.
- 7 expected traps: negative capacities/reserve, byte-count overflow, generation
  exhaustion, and typed/slab Span bounds.
- AddressSanitizer runtime tests pass with `ASAN_OPTIONS=detect_leaks=0`.
  LeakSanitizer itself cannot run in this execution sandbox (fatal ptrace/thread
  inspection error), so no leak-sanitizer pass is claimed. The failed attempt and
  successful address-only run are retained in Results.

The destruction test counts a noncopyable wrapper containing a long String plus
separate reference and closure-capture sentinels. This proves wrapper/capture
lifetimes, not a direct callback from Swift's private String allocation. The
payload benchmark separately observes actual malloc-family calls and frees.

Independent review checked lifetime/initialization/alignment/bounds invariants,
compile-fail controls and generated optimized code. It found the record-consume
loop still loads all seven fields. Review fixes normalized fresh-buffer
construction order, removed owner-ID wraparound, rotated payload variant order,
and corrected the allocation-counter script invocation.

## Measurement contract

`Tools/benchmark.sh` compiles all candidate sources in one optimized module
(`-O -whole-module-optimization`) so public-module specialization differences do
not obscure allocation policy. These results are not claims about a separately
compiled, unspecialized library client.

Each sample fills and reads 4,096 32-byte numeric records for 1,024 frames.
Every field contributes to a checked, equal checksum. Nine samples rotate variant
order. Process CPU time and monotonic wall time are saved, with no allocation
interceptor loaded for timing.

- `warm`: reserve and perform one full refill before measuring; then reset/refill.
- `coldReserved`: fresh storage per frame, with exact reserve before filling.
- `coldGrowing`: fresh storage per frame, allowing normal geometric growth.
- These "cold" labels mean **fresh buffers in a warm process**, not cold OS
  allocators, cold caches or first-launch behavior. Slab has no growing variant.
- Fresh-buffer paths release the previous backing allocation before allocating
  its replacement. The last backing allocation is destroyed after the measured
  region, so fresh reserved runs have N allocations and N−1 measured frees.
- `warmPayload` reserves element storage but constructs long Strings, references
  and capturing closures each frame. It includes payload cleanup after the last
  frame. The slab cannot represent this workload.

`capacity_changes` counts observed capacity changes in a separate matching-size
probe, including reserve. It is not a malloc count: an allocator can allocate
without changing reported capacity. Allocation CSV columns are instead gated,
current-thread, outermost calls to malloc/calloc/realloc/aligned_alloc/
posix_memalign/free, collected in a separate run using the verified interceptor.
They are not bytes, OS mappings, all-process allocations, or guarantees about
unintercepted/internal allocator entry points. See Tools/allocation-counter.

Raw CSVs, exact environment/commands, and a small summary are under Results.

## Recommendation

Keep reserved typed buffers as the default. Use the tiny lifetime wrapper only
where checked frame handles and borrowed phase boundaries simplify the API.
Use the slab only when a fixed command budget and explicit refusal on overflow
are useful product requirements. Reusable UniqueArray already removes observed
buffer allocation calls from this warmed workload. The slab adds unsafe code and
a capacity-failure policy without establishing a robust CPU or allocation win.

For the rendering MVP, keep persistent keyed state and nontrivial callbacks in
ordinary owned typed storage; build compact frame records, borrow synchronously
to render, then reset. Next measure that complete path with real key churn,
strings, callbacks and compositor-buffer release before widening adoption.
