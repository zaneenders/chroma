# Structural-path diagnostics (Linux/glibc)

These disposable-process probes support the structural-path investigation in #116.
They are not linked into Chroma. Build with Clang (the Swift toolchain's Clang is
suitable) and run a release-with-symbols `StressBenchmark` binary:

```sh
clang -shared -fPIC -O2 -Wall -Wextra -Werror AllocationProbe.c -ldl -o /tmp/chroma-alloc.so
clang -shared -fPIC -O2 -Wall -Wextra -Werror CPUSample.c -ldl -o /tmp/chroma-cpu.so

LD_PRELOAD=/tmp/chroma-alloc.so "$BENCHMARK" \
  --rows 100000 --panes 3 --depth 8 --identified 0 --events 12 --samples 3 --warmup 1 \
  >allocation-replay.json 2>allocation-counts.txt

CHROMA_CPU_SAMPLE_OUTPUT="$PWD/cpu.tsv" LD_PRELOAD=/tmp/chroma-cpu.so "$BENCHMARK" \
  --rows 100000 --panes 3 --depth 8 --identified 0 --events 12 --samples 30 --warmup 3 \
  >profile-replay.json 2>profile-capture.txt
```

Keep the executable beside its `chroma_ChromaFont.bundle` resource directory (or
preserve the normal SwiftPM product directory). Use exactly the same fixture
sources on the baseline and candidate. Neither probe belongs in a timing run.

## Allocation/ARC boundary

The interposer reports malloc/calloc/realloc calls, requested bytes, and intercepted
`swift_retain`/`swift_release` calls through its destructor. This includes startup,
JSON reporting, and the benchmark's separate metrics replay. Requested bytes are
cumulative allocation traffic, not retained/peak/RSS memory. Counts include calls
with null/immortal objects; teardown after the report destructor is excluded.
retain_n/release_n and runtime-internal calls are not
captured. Do not present these as every ARC operation or retained-object counts.

## CPU sampling boundary

`CPUSample.c` requests a 1 ms virtual (user-CPU) timer. The signal handler only stores
instruction addresses in a bounded, lock-free buffer; symbol lookup happens after
the timer stops. Kernel timer resolution and signal coalescing affect delivery.
`capacityDropped=0` means no buffer overflow, not proof that no signals coalesced.
Only preload into a disposable benchmark that does not use SIGVTALRM/ITIMER_VIRTUAL.

The virtual timer charges user CPU across process threads, while SIGVTALRM is
process-directed and may arrive on any eligible thread. Samples describe the
receiving thread; they are not an unbiased per-thread CPU profile. This fixture's
traversal is synchronous MainActor work, but runtime helper threads may exist.
Stopping the timer does not formally quiesce a handler already active on another
thread; compare TSV line count with the reported count, and use this only for
disposable, single-hot-thread diagnostics rather than general profiling.
See [setitimer(2)](https://man7.org/linux/man-pages/man2/setitimer.2.html) and
[signal(7)](https://man7.org/linux/man-pages/man7/signal.7.html).

Each TSV row contains image path, image-relative instruction address, and an
exported symbol when available. For private executable symbols, use the preserved
matching executable with `addr2line -afi -e "$BENCHMARK" 0xADDRESS`, then demangle
with `swift-demangle --compact`. These are self/instruction samples, not inclusive
stack percentages or exact per-event attribution. Capture includes startup and
metrics replay; 30 timing cycles versus four instrumented cycles keep most steady
work uninstrumented, but do not make the profile timing-only.

Preserve executable hashes/build IDs, raw reports, sample count, command line,
toolchain and fixture revision. Sampling diagnoses where CPU work moved; the
separate uninstrumented release matrix establishes timing changes. Headless
measurements say nothing about physical-display latency or GPU execution (#111).

The [2026-10-09 experiment](Results.md) records the implementation choice,
matched workloads, validation, measured results and remaining preparation work.
