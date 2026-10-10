# Keyed Wayland MVP

A standalone Swift 6.4 rendering experiment, isolated from Chroma's existing runtime. Start with `Sources/KeyedUI/UIStore.swift` and `Sources/KeyedDemo/main.swift`.

- One reusable keyed slot pool stores geometry, current behavior, focus, hover, clicks and animation state.
- `UIStore: ~Copyable` owns the pool. `UIFrame: ~Copyable, ~Escapable` borrows its build access through `MutableRef`.
- A separate fixed-capacity `TrivialSlab<DrawRect>` stores transient draw records. Presentation receives `Span<DrawRect>` and consumes it synchronously, without an intermediate Array.
- Direct row/column declarations; no result builders, layout wrapper tree or old runtime path.
- The demo has a counter, keyboard focus, animated hover/click feedback, and keyed items that can be reversed or removed/restored. Item click counts come from the retained slots, not a second state dictionary.

## Run

Requires Swift 6.4. `Package.swift` enables the experimental `Lifetimes` feature for custom lifetime annotations. No Swift package downloads are needed. Linux is the native target; macOS 27 availability is declared for the standard library containers, but no Apple build is claimed.

From this directory:

```sh
swift test
bash scripts/compile-fail.sh
swift run keyed-demo --cpu --screenshot preview.ppm
swift run -c release keyed-demo --benchmark-core --frames 10000
swift run -c release keyed-demo --benchmark --frames 10000
```

On a Linux machine running Wayland, install the ordinary development dependencies (Debian/Ubuntu names shown):

```sh
sudo apt install libwayland-dev libegl-dev libgles-dev
MVP_NATIVE=1 swift run -c release keyed-demo
```

Click the buttons, or use Tab then Enter/Space; Escape closes the window. The compositor provides `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR`. For a finite run and framebuffer capture:

```sh
MVP_NATIVE=1 swift run -c release keyed-demo --frames 120 --screenshot native.ppm
```

Use `--cpu` explicitly for a CPU preview. The native package flag controls compilation, not runtime backend autodetection. The same GL renderer can be checked without a compositor using `--egl-smoke --frames 12 --screenshot egl.ppm`; that mode verifies software/hardware EGL rendering only, not Wayland presentation or input.

## Ownership and phase boundaries

Each frame rebuilds the current geometry, label, style and callback for every declared key. Only deliberate state survives: click count, focus, pressed identity and animation. Removal destroys the node's owning payloads, bumps its generation, and reuses the slot later. Handles check owner, slot and generation; they never retain the store. Duplicate keys are a programmer error.

The order is build → remove missing keys → dispatch input → animate/paint → consume draws → reset scratch. Node borrows never span append/relocation. A callback can mutate a separate model; it must not reenter this UIStore during its exclusive access. Capturing an owning object strongly from one of its own stored callbacks can still form an ARC cycle. The demo deliberately keeps its captured model separate from the UI owner.

The native C bridge copies each rectangle's scalar values into its own fixed staging buffer, then uploads batches before returning from the Swift presentation closure. GL buffer orphaning gives submitted work its own storage. No GPU or compositor operation retains the Swift slab address. The CPU renderer also finishes before the borrowed Span ends. Asynchronous retained draw snapshots would need a separate owner/lease and are not implemented.

The slab reports capacity exhaustion through `droppedDraws`; it never grows or silently allocates overflow storage. Persistent slots and key-table capacity retain their high-water marks. `~Copyable` and `~Escapable` express ownership/lifetime constraints; they do not eliminate String/capture/key-table allocations.

## Native boundary

`Sources/WaylandBridge` is a thin one-window Wayland/EGL adapter. It reuses Chroma's generated xdg-shell protocol source and adapts the existing rounded-rectangle shader math to solid-color batched quads. It does not run Chroma's existing `WaylandHost`, `WindowRuntime`, layout or interaction tree. The existing host's runtime coupling is why this prototype has a separate small platform seam.

Text is an original 5×7 ASCII bitmap font expanded into ordinary quads. This is intentionally basic: no shaping, texture/font atlas, images, scrolling, editor, Markdown, accessibility, IME, clipboard, full flex layout, DPI scaling or production idle/power scheduling. Frames redraw at compositor cadence. No production-runtime performance comparison is claimed.

## Validation and measurements

See `Results/SUMMARY.md` for measured scope and exact native verification status. The CPU/debug and Linux native release builds pass. Keyed runtime tests, compiler-negative lifetime checks and independent ownership review pass. Actual compositor presentation/input remains a separate validation layer.

The vendored allocator in `Vendor/FrameArena` is independently runnable and includes typed destruction, alignment, owner/generation, compile-fail, trap and allocator-call tests. Its small implementation is separate from the more extensive test/benchmark tooling.

```sh
bash scripts/measure.sh
cd Vendor/FrameArena
swift test
bash Tools/compile-fail.sh
bash Tools/trap-tests.sh
```

Allocation counts are gated, calling-thread, outermost public malloc-family calls under Linux/glibc. The executable runs a fresh-storage positive control first. Timing runs without the interposer; native GL/compositor, CPU rasterization and screenshot I/O are excluded from the frame-construction benchmark. A warmed fixed-label test is different from the demo's dynamically formatted labels and capturing callbacks.

Swift 6.4 debug code generation crashed when private helper records appeared inside the public noncopyable owner layout. Keeping those helper types internal avoids the compiler issue without exposing them as public API.
