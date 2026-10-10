# Validation and measurement summary

Swift 6.4 RELEASE, x86_64 Linux (Debian 13), shared executor. Recorded 2026-10-10 UTC. This is an MVP, not a production-runtime replacement or a comparison against Chroma's existing runtime.

## Verified

- CPU debug and optimized executable builds pass.
- 10 keyed runtime tests pass: reorder, removal/reuse, foreign-owner handles, current callbacks, current geometry, cancelled removed presses, ARC capture destruction, focus cycling, draw overflow, repeated frames and CPU rasterization.
- The same 10 tests pass with AddressSanitizer (`ASAN_OPTIONS=detect_leaks=0`). LeakSanitizer is not claimed; this executor does not support its required process/thread inspection.
- Two UI-specific compile-fail cases reject escaping frame access and escaping presentation spans; a positive control compiles. These use actual `swiftc -c` code generation, because `-typecheck` alone does not exercise all lifetime diagnostics.
- Independent core review found no remaining blocker in handle validation, current-input phases, removal, lifetime views or demo capture ownership.
- The vendored allocator separately passes 7 runtime tests, 12 compile-fail cases plus positive control, 7 expected trap cases and address-only sanitizer tests. Its measurement harness validates the public allocator interception routes and a fresh-allocation positive control.
- Linux Wayland/EGL native release compilation succeeds with official Debian packages extracted in a workspace; no system libraries/configuration were modified.

## Native execution boundary

Actual Wayland presentation and compositor-delivered mouse/keyboard input are **not verified**. Weston successfully initialized its headless Pixman backend, then failed to create its Wayland socket. A direct AF_UNIX socket diagnostic returned EPERM, including the approved escalated check. That is an executor restriction, not evidence that the client fails on a normal Linux desktop. No restriction bypass was attempted.

`../scripts/native-smoke.sh` is the runnable headless Weston smoke test for a Linux environment that permits Unix-domain sockets. Native input remains an explicit manual validation step even after that screenshot test succeeds. Input snapshots can coalesce multiple rapid transitions between frames; lossless input event queues are intentionally outside this MVP.

The integrated Swift executable rendered 12 EGL surfaceless frames at 900×660 using llvmpipe (LLVM 19.1.7) and OpenGL ES 3.2 Mesa 25.0.7. The actual batched shader/VBO path and glReadPixels screenshot succeeded; the image was visually checked. This is Mesa software GL execution, and does not imply Wayland connection, presentation, input, or physical-GPU coverage.

Independent C review found an alpha-blending bug: ordinary blend factors reduced output alpha at antialiased edges over an opaque clear. This was corrected with separate RGB/alpha blend factors. An actual EGL regression test now verifies alpha stays 255 under half-alpha drawing and antialiased edges, and exercises 1,025 quads across the 1,024-quad batch boundary. The final native rebuild and 12-frame software-GL render pass after this fix.

Synthetic calls into the production C listener functions passed pointer, button, wheel, Tab, Enter/Space and Escape handler tests. Those tests are checked in at `../NativeSupport/bridge-input-test.c`; they do not simulate compositor delivery.

```sh
MVP_NATIVE=1 swift run -c release keyed-demo --egl-smoke --frames 12 --screenshot egl.ppm
```

## Warmed frame construction

Each sample warms 100 frames, then builds 10,000 frames. The fixed-core workload has 12 stable-key buttons with constant short labels. The demo uses its real 12 visible nodes, dynamic formatted click labels and model-capturing actions. Both consume the borrowed output with a command-count checksum. The counted window is the synchronous Swift model/build/paint-to-slab call only; it excludes CPU rasterization, the C bridge, GL/EGL/Mesa driver work or other driver threads, screenshot I/O and the compositor. The fixed slab budget is 32,768 DrawRect records. Slot count remains 12 and draw overflow remains zero.

Five independent timing runs, without allocator preload, report process CPU time. The table gives median microseconds per frame and the full observed range:

| Workload | Median CPU µs/frame | Range |
|---|---:|---:|
| Fixed-label core | 67.970 | 26.890–96.028 |
| Full demo construction | 113.482 | 85.331–188.422 |

The machine was shared and neither CPU affinity nor frequency was controlled. The broad ranges make these diagnostic samples, not a stable frame-rate or speedup claim. Raw CPU and elapsed time are in `timing.txt`.

Separate Linux/glibc allocation-call runs, after the same warm-up and with a per-binary fresh-storage positive control:

| Workload, 10,000 frames | malloc | calloc/realloc/aligned_alloc/posix_memalign | free |
|---|---:|---:|---:|
| Fixed-label core | 0 | 0 | 0 |
| Full demo construction | 30,000 | 0 | 30,000 |

That is zero intercepted allocation calls for the bounded fixed-label loop and three observed malloc/free pairs per full demo frame. The slab backing storage does not grow. The demo is **not allocation-free**. These counts cover only the calling thread's outermost public allocator entry points, not hidden allocators, direct OS mappings or every possible allocation route. They are not peak/live byte or leak measurements. Raw counts are in `allocations.txt`; timing printed during preloaded runs is not used for the CPU table.

An initial positive control using a trivially unused malloc/free pair was optimized away and correctly failed the instrumentation assertion. No results from that invalid control were accepted. The final positive control uses a non-inlined observable UniqueArray allocation, matching the independently validated harness approach.

## Compiler and API limitations

The package enables experimental `Lifetimes` for custom `@_lifetime` annotations. A Swift 6.4 debug IR verification crash with private helper record layouts was avoided by keeping those helper types internal. The owner and frame APIs remain small and do not publicly expose those helpers.

Class-owner captures can still create ARC cycles, and indirect callback reentry into the currently accessed UIStore violates runtime exclusivity. The demo captures a separate model. The checked frame access itself and its presentation Span cannot escape into stored callbacks.

## Source footprint

Lines include comments and blanks. Runtime/allocator code is separated from demo, platform and verification tooling.

| Group | Lines |
|---|---:|
| Keyed runtime + value types | 258 |
| Typed arena + fixed slab | 132 |
| Bitmap font + CPU reference renderer | 96 |
| Demo + allocation diagnostic | 165 |
| Native bridge + public header | 559 |
| Generated xdg protocol (existing source) | 913 |
| MVP runtime/lifetime/native regression tests | 188 |
| MVP scripts | 141 |

Allocator benchmark, tests and diagnostic interposer under Vendor/FrameArena are additional verification tooling, not part of the keyed runtime. Existing Chroma production files are unchanged.
