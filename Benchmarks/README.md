# Rendering benchmarks

A standalone package so the profiling dependencies never become dependencies of
Chroma library consumers. Replays deterministic, versioned display lists across
the logic/rendering boundary, without an application graph, window, network, or
random/clock-driven scene generation.

## Run

From the repository root:

```sh
# Correctness tests (also run in macOS and Linux CI)
swift test --package-path Benchmarks -c release

# Nine wire-codec workloads, JSON plus revision/toolchain metadata
Benchmarks/Scripts/run.sh Benchmarks/results/baseline

# Also run offscreen Metal and wire -> decode -> Metal on a Mac with a GPU
METAL=1 Benchmarks/Scripts/run.sh Benchmarks/results/baseline

# Individual workload
swift run --package-path Benchmarks -c release RenderBenchmark \
  --scene text --stage metal --count 2000 --frames 300 --warmup 30
```

Scenes: `shapes` (rounded shapes), `text` (128 repeating strings), `clipped`
(partially visible shapes), and `images` (many references to one checker image).
The microbenchmarks use a 1100x720 viewport and 1x raster scale. Count controls commands, not
visible commands or glyphs. Fixtures intentionally preserve offscreen commands
so Metal's production culling path is exercised. Wire timing encodes the supplied
list without a server culling pass.

Stages:

- `wire`: encode and decode only, with persistent sender/receiver image caches.
- `metal`: replay the original list through `MetalDisplayListRenderer`.
- `pipeline`: encode, decode, then render the decoded list; reports each phase
  separately, **not** an end-to-end frame latency.

Scribe-inspired scenes (`transcript`, `streaming`, `scrolling`, `selection`,
`composer`) replay 60 prebuilt frames with stable sidebar/status chrome, clipped
visible transcript lines and short colored runs. Count is logical history lines;
only viewport-visible lines emit commands. The composer caret moves through a
fixed cycle even in the transcript workload, so this is **not an idle test**.
Selection models highlighted/recolored runs, not selection input handling.

JSON reports sequence length, command-count range, first-frame phase timings, warm mean/p50/p95, frame counts, image
cold/steady wire bytes, OS, processor count, and fixture/protocol versions.
Initialization, shader compilation, sequence construction, and first-frame
round-trip validation are outside the timed phases. First replay is reported
separately; 30 additional frames warm caches before the 300 measured frames.

Metal CPU timing covers `prepareFrame`, including command creation, renderer
culling, instance preparation, buffer uploads, and `endEncoding`. It excludes
commit and completion waits. This boundary changed with the frame-lease API;
compare results only with baselines using the same timing boundary. GPU time comes from completed command-buffer
timestamps. Replay waits for each command buffer before reusing pooled buffers;
this is intentionally serial, **not** a maximum-throughput/presentation benchmark.
Failures to create/use Metal are errors, never silently reported as zero work.

The tests verify fixture determinism, exact protocol round trips across repeated
cached frames, image wire reuse, and culling idempotence. These are not pixel
snapshot tests. The harness does not yet exercise image revision/eviction,
resizing, sustained unbounded unique-string cache churn, or Wayland GPU rendering. Existing Chroma
and protocol tests remain the broader correctness suite.

## Automated sampling with the existing profiler

```sh
Benchmarks/Scripts/profile.sh Benchmarks/results/profile text metal
# For codec-only profiling (also suitable for Linux):
Benchmarks/Scripts/profile.sh Benchmarks/results/wire-profile shapes wire
```

The script builds release, starts a 20-second replay with a unique local profiler
socket, waits for readiness and warmup, captures 500 samples at 10ms, waits for
completion, and cleans up the process/socket. Open `samples.perf` in Speedscope.
`recorder.log` contains diagnostics; `profile-run.json` is explicitly marked as
profiled and must not be used as a timing baseline. No sudo is needed.

For manual capture, launch with `PROFILE_RECORDER_SERVER_URL_PATTERN` as in
Scribe, and use `--seconds 20` (or longer). Frame count and duration are both
minimums. The recorder samples all threads, including waits: sampled stack
frequency is not itself CPU utilization. Offscreen Metal profiles will include
intentional GPU completion waits; inspect active encoding stacks separately.

## Regression comparisons

```sh
METAL=1 Benchmarks/Scripts/run.sh Benchmarks/results/candidate
swift run --package-path Benchmarks -c release CompareBenchmarks \
  Benchmarks/results/baseline Benchmarks/results/candidate \
  --max-regression-percent 15
```

Compares p50 and p95 for each phase and exits nonzero on a regression, missing result,
incompatible fixture/configuration, or profiled timing input. Keep hardware,
power mode, toolchain, dependency versions, viewport, and workload identical;
Hardware/toolchain/dependency metadata must also match; these checks still do
not establish identical power or thermal conditions. Inspect
`revision.txt`, `worktree.txt`, and `toolchain.txt` with results. Run multiple
trials on a quiet machine before accepting a regression or claimed speedup.
GPU timings in particular vary with contention and power state.

Separate macOS and Arch Linux benchmark jobs wait for **both** existing platform
validation jobs to pass (including their prerequisite hygiene checks). They then
run correctness tests and upload platform-specific wire timing JSON artifacts
without timing thresholds. Build/test/execution failures still fail the benchmark
job. GPU runs and regression gating are opt-in on controlled hardware.
This harness isolates rendering; keep the existing demo `--benchmark` for graph
construction/draw/cull measurements, and live Scribe profiles for real workloads.

## Establishing a baseline

```sh
# Fresh processes, five complete suite trials; refuses to overwrite output.
METAL=1 Benchmarks/Scripts/baseline.sh Benchmarks/results/baseline-v2 5
# Make ONE optimization, then repeat with exactly the same settings.
METAL=1 Benchmarks/Scripts/baseline.sh Benchmarks/results/candidate-v2 5
swift run --package-path Benchmarks -c release CompareBenchmarks \
  Benchmarks/results/baseline-v2 Benchmarks/results/candidate-v2
```

Use a quiet, plugged-in machine; keep power mode unchanged. Compare the same OS,
CPU/GPU, compiler, dependencies, and fixture versions. Retain the baseline, full
JSON, revision and worktree metadata. A dirty working tree is a provisional
baseline, not an immutable release reference: commit the harness before recording
an authoritative baseline. Existing v1 results are intentionally incompatible.

The comparison takes the median of each trial's p50 and p95, reports percent
change and min/max spread across trials, and gates both percentiles. Spread is a
noise diagnostic, **not a confidence interval**. A 3% apparent gain with 10% trial
spread is inconclusive; repeat trials, alternate baseline/candidate order, and
profile the relevant stage. Do not compare Linux numbers directly against macOS
numbers. Shared CI artifacts are observations, not an automatic historical gate.

`SCENES='transcript streaming'` restricts either run script when iterating on one
hot path. Use the same selection for baseline and candidate. Sampling remains a
separate diagnostic run, never a baseline. `run.sh` also refuses to overwrite
nonempty results, preventing accidental mixing of workloads or old fixtures.

## What the Scribe inspection tells us to test next

Inspected `../scribe` at `e0bc712` (working tree may have local changes); no Scribe
source or user conversations are copied into these fixtures.

| Consumer code | Observed behavior | Coverage / next experiment |
|---|---|---|
| `TranscriptView.swift:25–136` | Rebuilds measured LazyVStack row descriptions and full selection-document entries | Needs graph benchmark at 100 / 1,000 / 10,000 rows; replay deliberately excludes this |
| `MacMarkdown.swift:664–713` | Markdown layout in measurement and drawing, visible-line culling | Current replay models colored runs; measure actual parser/layout separately in Scribe |
| `MacMarkdown.swift:570–614` | Selection background and prefix/selected/suffix drawing | Selection replay tests extra primitives; add exact split-boundary pixel tests |
| `GrowingTextField.swift:64–155` | Wraps in measure and draw, grows to six lines, selection clips | Composer sequence models growing geometry; add real typing/selection input tests in Scribe |
| `SessionSidebar.swift` | ScrollView, grouped rows and animated labels | Stable sidebar is included; graph scaling and animated label scheduling need consumer tests |

Priority next: a Scribe-owned headless benchmark target using its actual markdown,
transcript and composer components with generated data. Measure cold open, steady
redraw, streaming append, scroll, selection and resize separately. Avoid duplicating
Scribe's parser into Chroma: that would drift and benchmark the wrong implementation.
Then add anonymized/versioned draw-list captures at the protocol boundary for
renderer replay fidelity, plus image revision/eviction and pixel-output checks.

The synthetic replay is useful for localizing renderer/codec regressions, but a
fast replay says nothing about graph cost, idle CPU, input latency, or how many
unnecessary frames Scribe produces.

## Replay real demo captures

Launch the native demo and press **Ctrl+Shift+G** to save one real produced frame
in `Example/` (the demo package directory resolved at build time). Override it with
`--capture-directory /your/existing/folder`. The remote daemon requires that flag
to enable capture. See
[the demo capture instructions](../Example/README.md#capture-a-live-scene).

```sh
swift run --package-path Benchmarks -c release RenderBenchmark \
  --capture /path/to/scene.chromacapture --stage metal
```

Capture loading/validation is outside measured phases. The frame is replayed with
its recorded viewport and raster scale; a missing scale defaults to 1x. Metal
replay rejects raster targets larger than 8192 pixels per axis. Do not combine
`--capture` with `--scene` or `--count`. The report's scene identifier includes a
stable archive fingerprint to distinguish capture workloads; its `count` option
remains the CLI default, so use `commandCountMin/Max` for actual captured commands.
For comparisons, reuse exactly the same archive. Existing suite scripts continue
to run generated fixtures; capture replay is currently a direct CLI operation.

For the workflow, measurement boundaries, current limitations, and an initial
local replay result, see [scene capture and replay](../README.md#scene-capture-and-replay).

Benchmark report schema 3 separates requested `minimumFrames` and
`minimumSeconds` from the actual measured `frames`. Comparisons require matching
requested configuration, not matching sample counts in duration-based runs.
Regenerate older reports before comparing them with schema 3 reports.
