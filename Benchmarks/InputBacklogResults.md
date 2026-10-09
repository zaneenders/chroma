# Scheduled headless backlog: local combined comparison

Measured 2026-10-09 with Swift 6.4 on Linux x86_64. Related to #117; this is
**partial CPU progress, not a starvation fix**. Keep #117 and #111 open.
See [the harness and its boundaries](INPUT_BACKLOG.md#real-runtime-companion-scheduled-headless-replay).

## Controls and coverage

- Baseline production code: `7d9012c3c7de72605f77d3ffce301924365b6192`.
- Local combined candidate: `a8ab7bdd27262734a102572c4d53ff9fa7f3b4e7`, combining
  #92 (`61f0d915`), #115 (`df63c471`), #116 (`903c221e`) and the #117 diagnostics/
  harness (`dccd9411`, `b407d655`). This was local integration, not a merge.
  The #115 implementation was not published as part of this report or PR.
- Baseline and candidate used byte-identical benchmark source, including
  StressFixtures version 2 and this harness version 1. Baseline control edits
  affected benchmark code only, not production code.
- Paired baseline/candidate runs were serial by workload and axis configuration,
  three fresh-host trials each. Each trial emitted 180 logical samples at 60 Hz;
  diagonal samples applied two ordered axes separately. Work counters were off.
- Stress: depth 8, three identified lists of 100,000 rows, 1440×900 viewport.
  Markdown: 200 synthetic paragraphs, same viewport. These are local fixtures,
  not the original #111 native application scenes.
- **All 24 trials / 6,480 applications retained exact ordered coverage, no missing
  draw completions, and reached idle.** All covered draw timestamps followed input
  completion. Final command counts matched: stress 3,617; Markdown 15,095.

## Results

Each value is the median of three per-trial statistics, not a pooled percentile.
The shared-host timings vary substantially and do not establish statistical
significance. “Draw completion” means CPU draw-list production, **not frame start,
GPU completion or presentation**.

| Workload | Axes | Input wall p50 ms, before → after | Input process CPU p50 ms | Input process CPU p95 ms | Emission → draw p95 s | Recovery after source end s |
|---|---:|---:|---:|---:|---:|---:|
| Stress | 1 | 43.86 → 36.33 | 44.05 → 36.86 | 65.76 → 45.95 | 9.34 → 6.96 | 9.72 → 7.35 |
| Stress | 2 | 43.86 → 45.28 | 43.92 → 45.10 | 74.42 → 71.73 | 17.93 → 17.90 | 18.97 → 18.93 |
| Markdown | 1 | 24.42 → 15.49 | 24.67 → 15.63 | 41.45 → 24.13 | 5.15 → 1.72 | 5.39 → 1.79 |
| Markdown | 2 | 25.84 → 15.16 | 25.94 → 15.33 | 53.82 → 21.34 | 11.41 → 4.28 | 11.83 → 4.47 |

The measured Markdown and vertical-stress workloads improved; diagonal stress did
not establish a reliable gain. **Every configuration still accumulated backlog at
60 Hz when rendering was included.** Even a roughly 15 ms input application leaves
little frame-production budget, and diagonal samples pay for two applications.

Process CPU generally tracked input wall time, so these data do not support
attributing all remaining application cost to descheduling. Process CPU includes
concurrent producer work; it is not main-thread CPU time. Producer p95 lateness
was usually small but reached 28.7 ms in one baseline Markdown trial and 53.7 ms in
one combined Markdown trial. For example, combined vertical-stress draw-latency
p95 values were 6.68, 6.96 and 9.26 seconds; combined vertical-Markdown values were
1.72, 1.71 and 3.71 seconds. Those ranges should not be hidden by the summary.

Raw per-application JSON, all per-trial summaries, the runner, the exact control
patch/source archive and full source/binary hashes were retained with the local
experiment. They contain no physical-display timing. InputBacklog executable
SHA-256 values:

- Baseline: `9180ad9e71d58014c884812daf69935c4ce299680db57084f79d335b5a25899e`
- Combined: `e440c36644ff28f28e0d0cd2f36b41c3095904892cf33592fbb74946e72ff368`

## Verification and remaining work

The local combined tree passed 576 root Swift tests, 15 real headless
child-process tests, 11 release benchmark tests, and 8 Python model tests. Both
release benchmark builds passed. The standalone #117 branch separately passed
553 root tests, all 11 benchmark tests, release smoke replays, and strict format
and whitespace checks. No macOS/Metal test was run in this Linux environment.

These timed replays use the real runtime and scheduler, but bypass native
`wl_display_dispatch_pending` and `WindowRuntime.dispatchInput` batching. There is
no compositor readiness delay, native pointer momentum, GPU submission, or physical
presentation in the experiment. Native momentum/backpressure state machines are
covered separately by tests; that is not an end-to-end native capture.

The next bounded investigation is a matched native Wayland capture on the target
setup, or a separately labeled headless compositor: three vertical and three
diagonal trials for each retained scene, with input/application counts, native
C-dispatch spans, runtime queue boundaries, scheduler-ready/not-ready periods and
frame starts. Use an explicit capture deadline plus a recovery/idle tail, and keep
unrendered-event coverage when that deadline is reached. This distinguishes CPU
capacity from native dispatch monopolization or executor fairness before choosing
any queue/scheduling patch. A physical Hyprland/ShapeTree check remains #111 work.

No event dropping, stale registration reuse, arbitrary coalescing, cap/vsync change
or production scheduler modification was introduced by #117's diagnostic PR.

## Native follow-up feasibility: blocked by the execution context

A bounded follow-up staged authenticated Debian packages for Sway 1.10.1 and
wlroots 0.18.2 separately from the existing SDK. Sway initialized its headless
backend, pixman software renderer and shared-memory allocator, then failed to
create the Wayland display socket. A minimal
`socket(AF_UNIX, SOCK_STREAM)` probe failed **before bind** with
`EPERM / Operation not permitted`; one supported permission retry returned the
same result.

No compositor socket, successful client connection or native input capture was
obtained. This is an IPC restriction of the current execution context, not evidence
of a Chroma defect or a need for a physical GPU. The runtime attempts stopped at
that restriction, with the OS and existing SDK unchanged. The next native replay
requires a supported execution environment that permits local Wayland Unix-domain
sockets. The completed real-runtime/headless results above remain valid within
their stated scope; native dispatch and physical-display conclusions remain open.
