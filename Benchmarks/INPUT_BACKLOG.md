# Sustained input backlog: deterministic investigation

Related: [#117](https://github.com/zaneenders/chroma/issues/117),
[#111 diagnostic evidence](https://github.com/zaneenders/chroma/issues/111#issuecomment-6074947033).
This is regression/diagnostic coverage, **not a production starvation fix**.

## What the source establishes

On the reviewed main revision `7d9012c3`:

1. `WaylandHost.queueDisplayRead` submits one runtime action. That action calls
   `WaylandDisplayEvents.dispatchAvailable`, which calls
   `wl_display_dispatch_pending` synchronously. There is no suspension point
   inside a C listener dispatch.
2. Pointer listeners immediately update the mutable `InputAccumulator` and call
   `receiveInput`. Each actionable input reaches `WindowRuntime.handleInput`,
   which refreshes registrations before applying it. Separate axis callbacks
   currently cause separate applications; protocol grouping is #110's scope.
3. `WindowRuntime.flushInput` drains its action queue, including actions enqueued
   by other actions, before clearing `scheduler.inputPending`. Both the C call
   and this runtime drain can therefore contain more than one expensive input.
4. `FrameScheduler` cannot execute its main-actor wake task during synchronous
   work. It also intentionally gates scheduling on input completion and backend
   readiness. Its rate cap is an upper bound, not a promised input/frame rate.

This identifies mechanisms that can delay a ready frame. It does **not** identify
which batching/fairness mechanism dominated a particular native capture, or prove
an independent scheduler defect. At 23 ms per application, a 60 Hz stream already
exceeds a single executor's capacity before rendering costs. The CPU work in
#115/#116 may change that balance substantially.

## Actual runtime regressions

```sh
swift test --filter 'InputBacklogTests|InputBacklogMomentumTests'
swift test --filter 'WindowRuntimeTests|FrameSchedulerTests|FramePacingTests|ScrollMomentumTests|Keyboard'
```

`InputBacklogTests` uses the real runtime and its real scheduled task with a fake
clock. A single synchronous action applies 180 vertical or 360 separate diagonal
axis inputs with 23 ms of **simulated** cost each. It checks:

- No frame executes partway through that synchronous action.
- Finite work completes; the scheduled recovery frame sees all inputs in order.
- Every actionable input has a freshly captured registration revision.
- Painting does not replay inputs; no catch-up or unsolicited idle frame remains.
- Reentrant dispatch actions preserve FIFO order and finish before rendering.
- Pointer edges and text events retain order both before and after initial layout.
- Backend-not-ready demand survives the completed input drain and a separate
  simulated readiness delay, then produces exactly one recovery frame.

The momentum test drives real `ScrollMomentum` and `FrameScheduler` state machines
with one virtual clock. It covers finite vertical/diagonal work, finger release,
minimum-rate momentum, decay, and return to idle. It does not use a native pointer
or simulate `InputAccumulator`'s real-time sampling. Existing keyboard, input,
scroll, and pacing suites remain the semantic baseline.

These tests use continuations for completion rather than timed sleeps. They place
no wall-clock CI latency threshold on execution. The large synchronous batch is
a controlled reproducer, **not a claim that libwayland reads 180 events at once**.

## Deterministic queueing/latency experiment

```sh
python3 Benchmarks/Scripts/input_backlog_model.py --policy drain
python3 Benchmarks/Scripts/input_backlog_model.py --policy snapshot
python3 Benchmarks/Scripts/input_backlog_model.py --policy sample --axes 2
python3 Benchmarks/Scripts/input_backlog_model.py --policy drain --input-cost-us 2000
python3 Benchmarks/Scripts/input_backlog_model.py --callback-delay-us 100000
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Benchmarks/Tests/InputBacklogModelTests -v
```

The standalone model makes assumptions explicit. Arrivals are ordered at 60 Hz
for 180 samples; each sample contains one or two axis applications. All application
cost, frame cost, cap and readiness delay are configurable integer inputs. It
compares three **hypothetical** completed dispatch boundaries:

- `drain`: process all available samples, including arrivals during processing.
- `snapshot`: process the samples available at dispatch entry, then offer a frame.
- `sample`: offer a frame after each complete logical sample.

Each mode offers a due, ready frame before beginning the next batch. This fairness
rule is part of the experiment, not a property proved about Swift tasks or native
Wayland dispatch. It never renders inside a two-axis logical sample. `sample` is
not permission to split a protocol group or a proposed implementation.

JSON reports input completion and arrival-to-frame p50/p95, longest dispatch,
queue depth, frame starts, per-frame coverage, and recovery after the source ends.
Overdue ready wait and overdue not-ready wait partition demand time beyond the
frame cap; they are model quantities, not measurements from #113. Arrival time
is source time, not the native callback-receipt timestamp. The last source period
ends at 3 s; the final sample arrives one period earlier.

With default 23 ms input cost, 1 ms frame cost, and no readiness delay, `drain`
finishes 180 inputs at 4.14 s, then starts one frame, recovering 1.14 s after the
source ends. These values are **arithmetic consequences of the model**, not a
reproduction of #111's measured timings. At 2 ms cost, the same policy keeps up.
Offering more frames can shorten input-to-frame latency while lengthening total
recovery because rendering consumes CPU too. It cannot make 23 ms inputs run at
60 Hz. The test suite checks these distinctions, ordering, coverage, cap,
backpressure, zero-cost boundaries and idle without measured-time thresholds.

The model does not emulate C socket reads, kernel/compositor queues, task-priority
fairness, keyboard resolution, observation delivery, GPU execution or presentation.
It models the active sample stream only; release/momentum are tested separately
against Swift state machines. All finite samples are drained before reporting;
there is no capture cutoff or inference from missing latency samples.

## Why there is no scheduling patch here

A safe application queue needs a deliberate contract before translation and
application are separated. `InputAccumulator` is mutable, keyboard delivery can
consult current editing state/clipboard providers, and the next input must use
fresh callbacks and geometry. Calling `Task.yield()` after a native read cannot
interrupt the work already done inside `wl_display_dispatch_pending`. Rendering
while `inputPending` is true conflicts with the existing drain-before-render
contract and does not provide those snapshots.

Remaining #117 work:

- Measure native read-batch sizes, input costs and main-actor opportunities again
  after CPU fixes, using identical workloads and a sufficiently long recovery tail.
- Distinguish native C-dispatch monopolization from repeated runtime actions and
  scheduler/executor fairness. Preserve #113's unrendered-input coverage.
- If still needed, design bounded ordered snapshots at complete logical-input
  boundaries, including keyboard/text, pointer edges, enter/leave, release,
  pre-initial-frame events, observation changes, teardown and compositor gating.
- Prove bounds on retained snapshots/tasks, exact-once application and freshness,
  without dropping inputs, stale registration reuse or arbitrary coalescing.
- Reprofile native changes. Sway headless output with NVIDIA rendering in #111 is
  not physical scanout latency. Physical Hyprland/ShapeTree validation remains
  separate, as do Linux/macOS comparison and GPU timing.

Keep #117 and #111 open. No cap, vsync, readiness or input semantics are changed
by this diagnostic work.

## Real runtime companion (scheduled headless replay)

```sh
swift run --package-path Benchmarks -c release InputBacklogBenchmark --workload stress --depth 8
swift run --package-path Benchmarks -c release InputBacklogBenchmark --workload markdown --axes 2
swift test --package-path Benchmarks --filter InputBacklogBenchmarkTests
```

This companion runs **actual** `HeadlessHost.sendInput` and
`HeadlessHost.startPresenting`, so registration, layout, painting and the real
`FrameScheduler` consume measured wall time. A separate producer emits 180 ordered
logical samples at 60 Hz into an `AsyncStream` bounded to that finite event count.
One main-actor consumer applies them in order. Vertical mode applies one input;
diagonal mode applies vertical then horizontal separately in the same synchronous
sample. It does not add an artificial yield between axes or drop/coalesce inputs.
The consumer's `for await` boundaries are **not native C-dispatch boundaries**.
`sendInput` applies directly; this harness does not pass through
`WindowRuntime.dispatchInput` or exercise its `inputPending` batch gate.

The stress workload uses `StressScene` (three identified lists, 100,000 rows,
configurable nesting, 1440×900); Markdown uses a scroll view of 200 synthetic
paragraphs. These are declared local fixtures, not the original #111 native scenes.
Each trial gets a fresh host, an initial frame and ten warmup input/frame pairs.
Work counters stay off. The source begins after a 100 ms warmup delivery interval.
Run release binaries alone, with matching fixtures and parameters, for comparison.

JSON retains every application's intended/emitted source time, application start
and end, and the first subsequent **draw completion** that covers its applied
state. It separately reports producer lateness, emission-to-application wait, input-application wall duration,
coverage, finite recovery and idle. Application timings include any thread preemption;
they are not process CPU-time measurements. A separate process-CPU distribution
helps distinguish CPU work from descheduling on shared hosts. It includes any
concurrent producer work and is not main-thread CPU time or latency.
Per-axis application wait includes any
preceding axis application in the same logical sample, not only stream residence.
Missing draw completions remain missing rather
than becoming zero latency. Peak waiting samples is the observed stream buffer
occupancy, excluding the sample currently being applied. Three trials are the
default; each trial's distributions remain separate rather than treating correlated
inputs as independent experimental repetitions.

The public headless callback runs **after** draw-list production. Its timestamp is
not frame start, GPU completion, compositor feedback or physical presentation;
completion intervals need not individually obey a frame-start cap when render
cost varies. The harness intentionally does not expose a new production timing
hook or change scheduling. The existing deterministic pacing tests validate the
cap. Headless readiness is immediate and there is no native scroll momentum here;
those state machines are exercised separately above.

After the source finishes and all input is applied, the harness first waits up to
five seconds for outstanding draws, then continues collecting while looking for a
500 ms quiet interval within a three-second idle tail. Draws arriving during that
idle tail still complete coverage; reported coverage describes the end of the
whole collection window, not a five-second cutoff. Those limits bound collection, not
CI performance pass/fail criteria. It reports unrendered input or lack of idle if
recovery fails. It cannot report a missing-frame regression as a successful zero
latency result. The benchmark's tests cover parsing and report/coverage arithmetic;
they do not impose wall-clock speed thresholds.

[Local matched before/after results](InputBacklogResults.md) retain exact coverage,
finite recovery, process-CPU and wall-time distinctions, and the remaining native
validation scope. They show partial CPU improvements while all tested 60 Hz
configurations still accumulate backlog.
