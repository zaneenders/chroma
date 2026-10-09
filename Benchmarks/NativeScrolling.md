# Native Linux scrolling capture (#111)

Run in a Wayland desktop terminal. Build optimized code with symbols; keep the executable
and its SHA-256/build ID with the capture. Do not derive native FPS from headless tests or
surfaceless GL replay. This instrumentation does not change vsync, input order, callback
freshness, scheduler caps, momentum rate, or compositor backpressure.

## Reproduce

The in-repository `StressExample` uses the same `StressScene` as the headless lab.
Default settings: 100,000 rows, three panes, depth eight, min 30/max 60 Hz.
`plain` uses the same visible rows/layout without collection-wide identified-row scans.
`markdown` uses 200 synthetic transcript sections in a 1,800-point-wide scroll view
(horizontal and vertical gestures both move content). These are synthetic fixtures,
not a representative ShapeTree session.

```sh
# Each command needs a NEW output directory. Prefer three matching trials.
CHROMA_STRESS_WORKLOAD=identified NATIVE_REFRESH_HZ=60 \
  Benchmarks/Scripts/native-scroll.sh Benchmarks/results/native-identified-vertical-1 \
  Benchmarks StressExample . finger-vertical
CHROMA_STRESS_WORKLOAD=plain NATIVE_REFRESH_HZ=60 \
  Benchmarks/Scripts/native-scroll.sh Benchmarks/results/native-plain-vertical-1 \
  Benchmarks StressExample . finger-vertical
CHROMA_STRESS_WORKLOAD=markdown NATIVE_REFRESH_HZ=60 \
  Benchmarks/Scripts/native-scroll.sh Benchmarks/results/native-markdown-diagonal-1 \
  Benchmarks StressExample . finger-diagonal
# Explicit experiment, NOT a change to the defaults:
CHROMA_STRESS_MIN_HZ=60 CHROMA_STRESS_WORKLOAD=identified \
  Benchmarks/Scripts/native-scroll.sh Benchmarks/results/native-min60-1 \
  Benchmarks StressExample . finger-vertical-min60
```

`CHROMA_STRESS_ROWS`, `CHROMA_STRESS_PANES`, `CHROMA_STRESS_DEPTH`,
`CHROMA_STRESS_MARKDOWN_SECTIONS`, `CHROMA_STRESS_MIN_HZ`, and `CHROMA_STRESS_MAX_HZ`
configure the fixture. Use the display's actual rate for `NATIVE_REFRESH_HZ`; keep max
refresh at or below it. Do not build/test concurrently with measured runs.

For each 30-second run: allow initial layout, scroll continuously for about ten seconds,
release into momentum, then remain idle. Repeat vertical and diagonal gestures separately,
including wheel/continuous devices if relevant. Avoid scroll endpoints. Close the app
normally after the timer writes the trace. Mark the actual gesture/momentum/idle ranges
in a separate notes file; do not include transcript content.

```sh
python3 Benchmarks/Scripts/native_trace.py PATH/trace.json --refresh-hz 60 \
  --start 3 --end 13 > PATH/active-summary.json
python3 Benchmarks/Scripts/native_trace.py PATH/trace.json --refresh-hz 60 \
  --start 18 --end 28 > PATH/idle-summary.json
```

The collector refuses stale output and verifies that the dependency graph really uses
the specified Chroma checkout. For ShapeTree, deliberately configure a local dependency
instead of silently profiling its remote pin:

```sh
app=../server-tower/shape-tree/apps/shape-tree-desktop
swift package --package-path "$app" edit chroma --path "$PWD"
# Prepare the representative session BEFORE launch; no app log is copied by the collector.
Benchmarks/Scripts/native-scroll.sh Benchmarks/results/native-shapetree-vertical-1 \
  "$app" ShapeTreeDesktop . representative-transcript-finger-vertical
swift package --package-path "$app" unedit chroma
```

Inspect `dependency-graph.json` and `Package.resolved`; restore the intended dependency
before delivery. If another dependency also pins Chroma incompatibly, resolve that local
override explicitly. Do not mutate sibling manifests just to make the collector proceed.

The script records app/Chroma revisions and dirty status, dependency pins/graph,
release/`-g` configuration, binary path/hash/build ID/debug sections, workload settings,
toolchain, CPU/kernel, Hyprland version, monitors/rate/scale, and available platform
package versions. The trace records actual app min/max rates, initial viewport/scale,
GL/EGL vendor/renderer/version, presentation support/clock, and scale changes. On another
compositor add its version and output configuration manually. Retain the matching binary
privately for symbolication; revision alone is insufficient for a dirty build.

## Boundaries

All client timestamps use `clock_gettime(CLOCK_MONOTONIC)`. Durations are **wall time**,
not sampled CPU utilization; driver calls may block. The report uses nearest-rank p95
and the lower median. Nested scopes are inclusive and must not be added together.

| Field | Boundary / limitation |
| --- | --- |
| `displayQueue` | Main-actor display-read notification to queued dispatch action. Does not measure kernel/device queue age. |
| `displayDispatch` | `dispatchAvailable`, repeat-timer update, and flush; includes synchronous listener/input work. |
| `input`, `momentumInput` | `WindowRuntime.handleInput`, including fresh registration and interaction application. Counts events even when presentation coalesces them. |
| `registrationRefresh` | Full registration-only traversal, including interaction-tree reconciliation. Nested in actionable input. |
| `reconciliation` | Root block resolution/preparation. Some lazy child resolution occurs during layout; this is not all body evaluation. |
| `layoutRegistration` | Root resolved registration: nested resolution, measurement, placement, callback registration. The architecture interleaves these; they are not reported as independent additive phases. |
| `painting` | Root prepared-content painting. Custom/Markdown primitives may perform additional layout here. |
| `frameProduction` | Full `FrameProducer.render`, including tracking, registration, painting and navigation finalization. |
| `frameObservation` | Optional application's observer callback. |
| `openGLClear`, `openGLSubmission` | Clear/setup and real renderer cull/prepare/upload/draw calls; CPU/driver wall time, **not GPU execution**. |
| `eglSwap` | `eglSwapBuffers` wall time, including blocking. Vsync interval 1 is requested; driver acceptance and swap success are recorded. |
| `frameCPU` | Native frame callback request through rendering/swap/flush. Includes inner scopes and waits. |
| `schedulerDemandAge` | Age of the content request consumed by the scheduler, using its own clock. |
| readiness waits | Portion of request-to-start spent with scheduler not ready vs ready. Ready wait includes cap, queued input and actor/task scheduling; it is not a separate CPU phase. |
| callback intervals | Client delivery intervals and modulo-2³² protocol-ms intervals, kept distinct. Callback readiness is **not presentation**. |
| presentation | `wp_presentation` feedback per EGL surface commit, before swap. Up to eight outstanding feedback objects; discarded/skipped/pending counts retained. |

`wp_presentation.clock_id` must equal `CLOCK_MONOTONIC` before computing client-to-presentation
latency. For other clocks, preserve feedback-domain intervals but omit cross-clock latency;
no guessed offset. Core input/callback protocol timestamps have unspecified epochs: only
callback differences are used, with unsigned wrap handling. Presentation flags preserve
vsync/hardware-clock/hardware-completion/zero-copy provenance. Presentation feedback is
not a photon/scanout completion measurement. No `glFinish`, GPU timer queries or GPU-time
claims are introduced.

Frame IDs correlate ordered inputs with the frame consuming them. Input arriving after
draw-list production (including inside a blocking driver call) belongs to the following frame.
Reports group active vertical/horizontal/diagonal frames by latest finger/other source,
released momentum, and other frames. `other` is not automatically idle. Some compositors
omit source events; those frames remain `unknown`. Input counts include both axes of a
diagonal gesture; they are not gesture counts.

`phaseDurationsInclusive` reports p50/p95/max and strict `> 1000 / refreshHz` counts.
`perFrameInputAndFrameWallUnionByMode` unions input and native frame spans per frame,
without counting nested scopes twice. It includes swap waits, not just CPU execution.
`continuousDemandFrameIntervals` includes consecutive frame starts with demand arriving
by the previous start + one display period, or consecutive momentum frames. Deliberate
idle gaps are excluded. `missedDemandSlots` sums
`max(0, floor(interval / displayPeriod + 0.5) - 1)` for that subset: a full display slot
beyond the target interval, not a jank or universal dropped-frame count. Momentum at a
configured 30 Hz on a 60 Hz display deliberately skips slots; report that policy separately.
All-frame/callback/presentation intervals include idle and must not be called FPS.

`workInclusive` lists call counts and pipeline work totals for input, momentum,
registration refresh and frame production separately. Do not sum nested input/refresh
counters. GL instances/draw/upload calls/bytes are per frame. Upload counters exclude
texture uploads and buffer orphaning.

## Storage and observer effect

Set `CHROMA_NATIVE_TRACE` to a new file for any native Chroma app; no app API change is
required. `CHROMA_NATIVE_TRACE_SECONDS` defaults to 30 (0.1–300 supported).
`CHROMA_NATIVE_TRACE_CAPACITY` defaults to 60,000 (maximum 200,000 events). Retain a bounded
prefix and count dropped records when full; do not infer complete frames from saturation.
After the timer (or normal close), detach instrumentation, restore the prior pipeline-metrics
setting and write once with exclusive creation and mode 0600. No continuous disk I/O or
idle frame requests are introduced. Forced process termination can lose the in-memory trace.

Payloads contain timings, counts, frame IDs and driver metadata—not pointer coordinates,
key/text events, transcript text, command-line arguments, credentials or the environment.
The shell collector does not retain application stdout/stderr or an environment dump.
Local paths and workload labels are metadata; review them before sharing artifacts.

Enabled work counters add overhead, especially to deeply nested layouts. Repeat matched
runs with `CHROMA_NATIVE_TRACE_WORK=0` to estimate that observer effect (unless metrics
were already enabled by the app). The disabled path uses optional checks without clocks,
per-node timers, logging or capture allocation.

## Diagnosis / validation status

Built `StressExample` release with DWARF symbols on Linux/Swift 6.4; core and benchmark
regressions plus deterministic capture/report tests pass. Native launch was attempted but
failed to connect: this shell has no user Wayland socket; the only Hyprland process is the
SDDM greeter. `perf` is unavailable. **No native scrolling distribution, representative
ShapeTree capture, GPU timing, or macOS comparison has been measured here.**

Next optimization remains unselected until native captures exist. Use matched identified
vs plain input work to isolate identity scans (#93), Markdown resolution/layout/paint to
isolate preparation (#96), and backend/swap/readiness/presentation timings to isolate native
queueing. Do not assume swap plus callback gating adds two waits. If CPU scopes dominate,
collect release-symbol stack samples separately with `perf` when available; inclusive stack
costs are not additive phase costs. Hardware results stay manual artifacts, not CI thresholds.

```sh
swift test --filter 'FrameTimingCaptureTests|WaylandTimingTests|FrameSchedulerTests|WindowRuntimeTests'
python3 -m unittest discover -s Benchmarks/Scripts -p 'test_native_trace.py'
```

Protocol bindings are generated with `wayland-scanner client-header` / `private-code` from
`wayland-protocols/stable/presentation-time/presentation-time.xml` (1.49), binding version 1.
