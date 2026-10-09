# Linux scrolling diagnostic artifacts (#111)

## Scope and provenance

Recovered and reanalyzed saved captures from 2026-10-08. These run the native Wayland
client and real NVIDIA renderer against **Sway's headless backend**. They are not
physical-display scrolling measurements, a ShapeTree transcript, or a Linux/macOS
comparison. Presentation feedback flags were zero throughout: no vsync, hardware-clock,
or hardware-completion provenance. Do not interpret the feedback as scanout latency.

Primary artifacts: `Benchmarks/results/native-111-completed/` (ignored, local only).
The earlier diagonal Markdown trace is in `native-111-matrix-markdown-depth0-diagonal/`;
its counterpart in `native-111-completed/` has no trace and is excluded.

| Setting | Recorded value |
| --- | --- |
| Chroma revision | `40117c57b25a044843bd537f1a275c3e4e532a85`; saved patch changes the former reporting scripts/tests, not instrumented Swift sources |
| Executable | `Benchmarks/.build/out/Products/Release-linux-x86_64/StressExample`, release with DWARF symbols |
| SHA-256 | `a18a5d5dd82ed6f26820067c28824761a2f207862cec82628345562bee84ea51` |
| ELF build ID | `c4631ba555c7634a09ba7709855161456c0ad9de` |
| Toolchain / CPU | Swift 6.4, x86_64 Linux; Intel i5-12600KF |
| Kernel / compositor | Linux 7.2.3-arch1-3; Sway 1.12, wlroots 0.20.1 |
| GL / EGL | RTX 3060 Ti, NVIDIA 610.57.04, OpenGL ES 3.2, EGL 1.5 |
| Output | `HEADLESS-1`, 2880×1800 at configured 60 Hz, scale 2, 1440×900 logical viewport |
| App rates / swap | min 30 / max 60 Hz; requested swap interval 1 accepted |
| Fixture | 100,000 rows, three panes; depth 0 or 8; Markdown uses 200 synthetic sections |
| Gesture | Virtual pointer, finger source, three seconds at 60 events/s, delta 3; reversal every two seconds |
| Capture | Work counters disabled, no dropped records; actual duration about 13 seconds for the primary runs |

Initial trace metadata says scale 1; each trace records a `bufferScale=2` event before
the gesture. Output configuration is not proof of actual physical refresh. Settings
requested 35 seconds, but captures ended earlier; use recorded start/end, not the request.
The matching executable is retained privately as `native-111-completed/StressExample.elf`
(mode 0600), recovered from perf's build-ID cache and SHA-256 verified; rebuilding
`StressExample` is not a substitute for that binary.
Dependency graph resolves Chroma to this checkout. Saved pins: swift-collections 1.7.1
(`98ef3c98609a1e31b7e157b5b619579001a789d6`), swift-markdown 0.9.0
(`25cb61d3482054b09ae76ca4f281b1bfe7fe5a43`), swift-cmark 0.9.0
(`08ddb528923cc1a6527e02b7a1aee9e516ca749a`).

## Phase durations

Milliseconds, **p50 / p95**, inclusive wall time, full recorded range including startup.
Nested columns must not be summed. Each row is one trial, not a confidence interval.

| Workload / gesture | Input | Registration refresh | Layout / registration | Frame production | GL submission | EGL swap |
| --- | --- | --- | --- | --- | --- | --- |
| Plain depth 0 / vertical | 1.99 / 2.94 | 1.99 / 2.93 | 1.66 / 2.39 | 2.47 / 3.00 | 0.32 / 0.58 | 0.08 / 0.11 |
| Plain depth 0 / diagonal | 1.94 / 2.12 | 1.93 / 2.13 | 1.63 / 1.75 | 2.43 / 2.73 | 0.33 / 0.55 | 0.06 / 0.13 |
| Identified depth 0 / vertical | 4.99 / 5.49 | 5.03 / 5.67 | 1.70 / 1.86 | 5.56 / 6.15 | 0.33 / 0.61 | 0.06 / 0.12 |
| Plain depth 8 / vertical | 22.82 / 24.92 | 22.71 / 24.94 | 16.99 / 18.29 | 23.15 / 52.21 | 0.64 / 4.34 | 0.13 / 1.17 |
| Markdown / vertical | 64.86 / 68.56 | 63.23 / 66.72 | 61.19 / 64.48 | 83.76 / 140.79 | 1.97 / 2.11 | 1.03 / 1.10 |
| Markdown / diagonal (earlier run) | 58.24 / 62.69 | 56.91 / 61.18 | 55.48 / 59.35 | 80.58 / 136.84 | 1.70 / 1.81 | 1.08 / 1.20 |

Vertical primary runs received 180 axis events and 184 input calls. Plain diagonal
received 360 axis events and 365 input calls: both axes are applied separately.
Registration refresh calls were 202 plain vertical, 384 plain diagonal, 202 identified,
194 depth 8, and 182 Markdown vertical. Per-node work counts are unavailable with
`CHROMA_NATIVE_TRACE_WORK=0`; use event counts, not zero work totals, for call counts.

Strict `>16.667 ms` input counts: 0/184 plain vertical, 0/365 plain diagonal, 0/184
identified, 181/184 depth 8, 181/184 Markdown vertical, and 362/365 Markdown diagonal.
The union of input and native frame spans avoids double-counting nested work:
plain vertical active frames 4.94 / 6.86 ms (0/175 over budget), plain diagonal
6.70 / 10.20 ms (1/173), identified 10.97 / 15.69 ms (4/172). Depth 8 accumulated
4,216 ms of input/frame work into **one** active frame; that is not a useful active
frame distribution.

## Pacing, coverage, and waits

Adjacent frame starts in the same mode, excluding transitions and missing frame IDs:

| Workload | Active intervals: samples, p50 / p95 ms | Momentum intervals: samples, p50 / p95 ms | Axis receipt → headless feedback: samples, p50 / p95 ms |
| --- | --- | --- | --- |
| Plain vertical | 174, 16.71 / 18.48 | 18, 33.39 / 33.42 | 180, 10.79 / 31.07 |
| Plain diagonal | 172, 16.77 / 18.38 | 19, 33.51 / 33.56 | 360, 15.99 / 31.47 |
| Identified vertical | 171, 16.79 / 19.63 | 18, 33.41 / 33.57 | 180, 19.98 / 30.33 |
| Plain depth 8 | None: only one active frame | 10, 56.13 / 58.36 | 180, 2,178.29 / 4,015.99 |
| Markdown vertical / diagonal | None | None | None: all 180 / 360 axis events lack a matching frame start |

Momentum near 33.4 ms in the light scenes follows the configured 30 Hz minimum; it
must not be called a 60 Hz regression. `missedDemandSlots` totals are 18 plain vertical,
20 plain diagonal, 19 identified, and 21 depth 8, including deliberate momentum slots.
Both Markdown traces report zero slots because no active frames exist: zero is **not**
evidence of meeting the budget. They retain 11,786 ms / 21,296 ms input wall unions
without a frame start, and only three pre-gesture frames. Presentation latency is
unavailable, not zero. Shutdown/range truncation prevents claiming eventual recovery.

For plain vertical active frames, callback-delivery intervals are 16.82 / 18.43 ms
and headless-feedback intervals 16.82 / 18.43 ms. Client display-notification queue
p95 is 0.016 ms, but this excludes device/kernel age and events waiting inside the
compositor or while the client handles earlier input. Deep nesting received the
three-second injection over about 4.13 seconds of client processing. Maximum display
dispatch duration was 1,110 ms; request wait while ready reached 4,150 ms. This is
consistent with synchronous input work delaying frame scheduling, not swap blocking.
The light scenes and depth-8 primary run end with about six seconds without input,
momentum, or frame work; Markdown has no quiet tail to validate return to idle.

## CPU samples and next target

`native-111-profile-plain-100k/` contains an earlier depth-8 run and `cpu.perf`:
perf 7.2.3-1, `cpu-clock:u` at 199 Hz, 16 KiB user stacks, 774 samples, no lost samples.
Its executable build ID matches the primary runs. Sampling covers startup as well as
input work, so percentages are not active-only phase measurements. Top self costs:
`swift_release` 10.85%, `swift_retain` 7.75%, decrement slow path 6.72%, and
`StructuralPath.Segment` destroy/copy witnesses 5.94% / 3.88%. Inclusive stacks pass
through stack layout, interactive preparation, and scroll-row registration; overlapping
inclusive percentages are not additive.

Prioritize actionable-input registration/layout (#103), including structural-path and
ARC churn in nested controls (#116), while preserving fresh callbacks and ordered input.
Markdown preparation/layout (#96) independently exceeds the budget; #115 isolates
operation-local leaf layout reuse. #117 investigates sustained-input frame starvation
without assuming a scheduler defect. Identified rows add reconciliation work (#93):
3.12 / 3.59 ms versus plain 0.08 / 0.12 ms at depth 0.
GL submission and swaps are smaller in these synthetic runs; this does not rule out
physical compositor/driver queueing. No refresh policy, cap, or vsync change is justified
by headless-output timing.

## Tooling validation

The Swift `NativeTrace` reporter replaces the Python scripts, including dependency-path
verification. Its 17 deterministic tests pass, and 36 summaries from 12 saved traces
(full, active, and idle ranges) match the former reporter. Core and benchmark suites,
release-with-symbols `StressExample`, and release `NativeTrace` builds pass. An isolated
Sway headless smoke run verified collector launch, private trace output, Swift summary,
normal close, and gesture-injector delivery; it is not another performance trial.

## Remaining acceptance work

- Three matched physical-display trials, vertical and diagonal, active finger, momentum,
  and verified idle; retain driver/compositor/output and executable metadata.
- A representative ShapeTree session using the deliberate local Chroma override.
- Matched work-counter enabled/disabled runs and, if useful, min-60 and wheel experiments.
- Linux/macOS comparison and GPU execution timing remain unmeasured.

This shell has no desktop Wayland environment; the collector's native launch preflight
fails with `Run from a desktop terminal with XDG_RUNTIME_DIR and WAYLAND_DISPLAY.`
The saved headless runs narrow CPU targets but do not complete #111.

Recompute a saved run with the updated coverage and mode-interval reporting:

```sh
swift run --package-path Benchmarks -c release NativeTrace \
  Benchmarks/results/native-111-completed/plain-depth0-vertical-work0-min30-1/trace.json \
  --refresh-hz 60 > /tmp/native-111-reviewed-summary.json
```
