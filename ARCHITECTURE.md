# Chroma Rendering Architecture Proposal

Status: proposed, not implemented.

## Recommendation

**Keep Blocks as lightweight UI descriptions. Put a small retained engine underneath them. Separate building, layout, interaction, and painting.**

Not a SwiftUI clone, not a Rust port, and not a system that rebuilds everything for every input event.

The useful combination is:

- **Clay:** compact layout data and renderer-independent output.
- **Interaction Medium:** stable identity, explicit mutation phases, composable navigation scopes.
- **GPUI:** separate layout/prepaint/paint phases and retained interaction state.

Chroma already has useful pieces: `DrawList`, the scheduler, commands, logical scroll selection, headless testing, and two backends. Replace the execution model rather than discard everything.

The consumers guiding the design are:

- `../scribe/scribe-desktop`
- `../shape-tree/apps/shape-tree-desktop`

Preserving the exact API is secondary to performance, simplicity, and backend independence.

## 1. Current costs

The biggest confirmed problem is **drawing to discover how input should work**.

[`WindowRuntime.processInput`](Sources/Chroma/Application/WindowRuntime.swift) refreshes registrations for scroll, drag, and other non-pointer-only input. [`FrameProducer.refreshRegistrations`](Sources/Chroma/Rendering/FrameProducer.swift) does that by drawing the UI into a discarded `DrawList`.

A release benchmark on Apple M5 produced:

| Workload: 1,000 rows, eight scroll events | Input p50 | Render p50 | Row draws: input + render |
|---|---:|---:|---:|
| Eager list | 93.73 ms | 11.72 ms | 8,000 + 1,000 |
| Lazy list | 0.46 ms | 0.06 ms | 176 + 22 |

These are headless CPU measurements from one run, not GPU or presentation timings. They are baseline observations, not projected improvements.

Other architectural costs visible in the code:

- **Repeated resolution and measurement.** [`BlockEngine`](Sources/Chroma/Layout/BlockEngine.swift) creates `Resolved` class chains; stacks resolve and measure children during both measurement and drawing.
- **Identity work proportional to the entire collection.** Keyed uniform lists map and validate all IDs during construction. The million-item benchmark took roughly **224–236 ms** on subsequent keyed runs, versus **0.09 ms** unkeyed. That benchmark replaces content each iteration; it is not steady-state scrolling.
- **Variable-height virtualization is incomplete.** It limits drawing, but initially measures every row and scans cached rows to validate them.
- **Caching leaks into applications.** Both consumers maintain transcript-row caches. Scribe also performs reveal measurements and selection registration through custom drawing code.

**Start with CPU execution and virtualization—not shader optimization.**

## 2. Proposed engine

```text
Application-owned models
          │
          ▼
Blocks → build/update → compact node storage
                              │
                            layout
                              │
                            prepare
                         ┌────┴─────┐
                         ▼          ▼
                   interaction    paint
                    snapshot        │
                         ▲          ▼
Platform input → commands       DrawList / Scene
                                    │
                              Metal / OpenGL
```

### Blocks describe; nodes execute

Keep the general ergonomics of `Block`, stacks, modifiers, and builders. They describe UI rather than serve as the runtime tree repeatedly traversed by every subsystem.

Lower those descriptions into reusable, index-addressed nodes containing:

- Parent/child relationships.
- Layout configuration and computed bounds.
- Paint properties.
- Optional interaction and command metadata.
- Dirty flags and cached measurements.

Use contiguous, capacity-reusing storage with one owner. Prototype `UniqueArray<Node>` from Swift Collections alongside `Array<Node>`; prefer the unique owner for engine-private mutable storage if the measured results and API fit justify it. No handwritten unsafe arena allocator or object per modifier.

### Swift 6.4 ownership tools

These tools address different problems:

| Tool | Role in Chroma | Constraint |
|---|---|---|
| `UniqueArray<Node>` | Single-owner, dynamically growing node/scratch storage without copy-on-write sharing | Growth can still allocate and move elements; reserve and reuse capacity |
| `RigidArray<Node>` | Explicit-capacity storage where allocation timing must be controlled | Needs an overflow/growth policy; screen size does not bound node count |
| `Span<Node>` / `MutableSpan<Node>` | Borrow contiguous nodes for read or mutation passes | End borrows before structural mutation; do not retain them in callbacks or submitted frames |
| `Ref<Node>` / `MutableRef<Node>` | Temporary access to one node when plain `borrowing` / `inout` is insufficient | Not owning references or persistent graph edges |
| `~Copyable` | Enforce unique ownership of storage or resources | Not a promise of stack allocation, no ARC, or faster execution |
| `~Escapable` and lifetime annotations | Express a temporary view whose validity depends on its owner | Not a persistent store; custom lifetime APIs need toolchain-specific validation |

Proposed ownership structure:

```text
WindowRuntime (@MainActor)
  owns NodeStore (~Copyable)
    owns UniqueArray<Node>
    edges are NodeID(index, generation)

Build: grow/update storage using IDs
Layout/prepare/paint: borrow storage for the duration of each pass
Submitted frame: owns its data/resources independently of graph borrows
```

Keep node handles and simple geometry copyable. Make nodes noncopyable only when they actually own resources that must not be implicitly duplicated. A noncopyable store does not require every element to be noncopyable.

Persistent edges remain IDs, not `Ref`s. Use stable slots and a free list; do not shift live slots with array removal. Storage reallocation preserves indices, but slot reuse requires generation checks. Compaction requires remapping handles and should not be part of the first implementation.

During a pass, separate read access from writes or use short borrows. Holding a mutable view of the entire store while recursively requesting another mutable view conflicts with exclusive access. End views before building more virtualized rows or growing storage.

`@lifetime` describes a dependency; it does not extend an allocation's lifetime or provide automatic graph ownership. Prefer existing span APIs and `borrowing` / `inout` first, then add custom borrowed views where they simplify a measured hot path.

The installed Swift 6.4 toolchain and Swift Collections 1.7.1 were tested in an isolated release-mode probe with strict memory safety and warnings as errors:

- `UniqueArray` with noncopyable nodes, `Span`, `MutableSpan`, local `Ref` / `MutableRef`, and capacity reuse worked without experimental flags in the client target.
- A custom `~Escapable` view and span-returning wrapper worked with the experimental `Lifetimes` feature and `@_lifetime`. Public `@lifetime` spelling was rejected under the initial settings. Do not treat custom lifetime annotations as a default-stable requirement of the design.
- Returning `Ref(nodes[index])` from a wrapper was rejected for escaping a temporary borrow; use the verified span path rather than unsafe lifetime overrides.
- These probes establish compatibility, not a speedup. Benchmark allocations, storage growth, ARC/copy-on-write overhead, and p95 frame cost before choosing storage.

The installed standard library exposes `Ref` / `MutableRef` for Apple OS 27, matching Chroma's macOS deployment target. Swift Collections 1.7.1 also documents a Swift 6.4 `Ref` back-deployment workaround; Linux still needs independent validation. No dependency or compiler-flag change has been made to Chroma.

Fold modifiers into node properties **where order permits**. Padding-before-background and background-before-padding must remain different.

Keep type erasure at composition/custom-element boundaries rather than trying to eliminate every `any Block`.

### Separate four operations

| Phase | Responsibility |
|---|---|
| **Build/update** | Evaluate Blocks and update node descriptions and callbacks. |
| **Layout** | Measure and place nodes; retain results. |
| **Prepare** | Produce hit regions, clipping, focus relationships, command scopes, and text-input geometry. |
| **Paint** | Produce drawing commands from prepared nodes and current visual state. |

The critical invariant:

> Painting does not register controls, execute actions, or mutate application state. Input does not require painting.

Deliberately break `PrimitiveBlock` to establish that contract. Keeping its current “do everything inside `draw`” behavior would preserve the main architectural problem.

Custom Markdown and text primitives still get an escape hatch: measurement, interaction preparation, and backend-neutral painting.

## 3. Retain results, not an application object framework

Use two different identifiers:

- **Node handle:** compact runtime index with generation protection against reuse.
- **Semantic key:** stable application identity, scoped beneath a parent.

Keyed collections preserve identity through reordering. Structural slots remain convenient for static UI. Modifier changes should not accidentally reset focus.

**Identity is not cache validity.** The same keyed row can have new text, callbacks, styles, or layout.

Start invalidation at useful boundaries—panels and list rows—not a dependency graph for every modifier. Track model reads there and distinguish structural, layout, interaction, and paint changes.

| Change | Required work |
|---|---|
| Hover/focus appearance | Repaint affected visuals; reuse layout |
| Caret blink | Update caret paint only |
| Scroll | Update transforms, clipping, and visible rows |
| Streamed transcript text | Update that row, its measurement, and affected layout |
| Window resize | Relayout; reuse unchanged content descriptions |
| Idle | No frames |

Bounds changes must propagate to interaction geometry as well as pixels.

Keep UI state and callbacks on `@MainActor`. Send only immutable, compiler-checked `Sendable` rendering data across threads; use `Mutex` where shared validity state genuinely requires synchronization. Do not use `@unchecked Sendable`.

## 4. Input correctness must survive caching

Input targets a **committed, valid interaction snapshot**.

1. Receive ordered platform events.
2. Resolve keys into commands using active scopes.
3. Dispatch actions and apply model changes outside build/layout/paint.
4. Update invalidated content and geometry as needed.
5. Paint when the scheduler requests a frame.

Do not simply reuse last frame’s callbacks forever. If an action removes a button or opens a modal, the next relevant event must see that change—even before presentation.

Refresh stale build/layout/interaction data **without painting**.

**Do not coalesce input events in this implementation.** Preserve every event delivered to Chroma, including pointer movement and scroll deltas, in arrival order. Drain an ordered queue without merging, dropping, or reordering its events. Platform-level sampling outside Chroma is not under the engine's control.

Multiple events may share one scheduled paint, but they still execute separately and can invalidate state between events. Reducing presentation frequency is not permission to reduce event fidelity. Audit backend accumulation as part of migration: the current Wayland `InputAccumulator` stores latest pointer state, edge flags, and summed scroll deltas rather than a complete ordered event history.

The realistic target is **no paint during input and no unconditional full rebuild per event**, not exactly one update per frame regardless of correctness.

## 5. Virtual lists as a first-class primitive

Separate a scroll container from a virtual list. A `ScrollView` around an eager `VStack` cannot avoid building its children automatically.

A virtual list needs:

- Stable item IDs and an ID-to-index lookup.
- A collection revision or explicit change notification.
- A row builder invoked only for visible rows plus overscan.
- Fixed heights, or estimated heights with cached measurements.
- Logical selection independent of instantiated rows.

For variable-height transcripts:

- Measure visible/new/invalidated rows rather than the entire history.
- Cache by item content revision, width, and relevant text/layout environment.
- Maintain an indexed height table for offset lookup and updates.
- Anchor scrolling to **item ID + offset within the item** as estimates become exact.
- Preserve bottom-following only when the user was following the bottom.

Allow an exact-measurement mode for smaller lists where exact initial extent matters.

**Full collection work is acceptable when the collection changes—not on every wheel event.**

### Can traversal stop at the viewport boundary?

**Yes for a layout that can prove the remaining content is outside the effective clip; not for an arbitrary Block tree.** Window dimensions are constraints, not the final bounds of every descendant.

Use the window viewport intersected with ancestor clips, mapped into the content's coordinate space. Scroll offsets and any transforms must be included.

| Stage | Safe optimization |
|---|---|
| Build | Defer child construction in explicit virtualized containers; eager builder execution has already paid the construction cost |
| Layout | Skip measurements whose cached/fixed/estimated extents suffice; account for skipped extents so scroll limits and sibling placement remain correct |
| Prepare | Omit invisible pointer hit regions, but preserve command scopes, logical navigation, pointer capture, and editing state independently |
| Paint | Prune a subtree when its conservative visual bounds miss the clip and descendants cannot paint outside those bounds |

For a fixed-height list, jump directly to the visible index range, build that range plus overscan, and stop at its end. Do not scan from row zero to reach a far-away viewport.

For a variable-height list, locate the range using the height index, measure visible rows, and refine estimates while preserving the scroll anchor. The unbuilt tail still contributes to the estimated total extent.

A general stack cannot stop simply because the running cursor passed the bottom of the window:

- Later siblings can change grow-space distribution, alignment, or the size of earlier children. The current `StackLayout` explicitly measures siblings to distribute space.
- Overlays, reversed layouts, offsets, or descendants drawing outside their parent can place later content back inside the viewport.
- Unknown row heights do not establish an exact content extent.
- An offscreen selected row still needs logical navigation and reveal; an active drag or editor must not be destroyed merely because it is clipped.

For ordered rows with known nonnegative extents and clipping that prevents overflow, early termination is valid. For general layouts, skip proven-invisible subtrees rather than terminating the entire traversal. Existing `DrawList.culled(to:)` runs after command creation; the new engine should avoid constructing those commands in the first place.

## 6. Keyboard navigation belongs in the core

Chroma already has commands, focus groups, navigation boundaries, and `ScrollSelection`. Preserve their behavior while changing their storage and lifecycle.

Keep these concepts distinct:

- **Hit testing:** what is under the pointer?
- **Focus/navigation:** where do keyboard commands go?
- **Logical selection:** which application item is selected, including offscreen items?

Navigation is a semantic projection of the nodes, not a duplicate object hierarchy reconstructed during painting.

Support:

- Ordered traversal and directional movement.
- Enter/exit navigation scopes.
- Modal scope isolation and focus restoration.
- Commands bubbling from the active scope toward the root until handled.
- Application-controlled selection and deletion/collapse fallback policies.
- Revealing an offscreen selection before interacting with its visible control.

Buttons, shortcuts, and a future command palette invoke the same commands.

This follows the central point in Interaction Medium, Part 9: **visible box identity alone cannot represent all keyboard-selection semantics.**

## 7. Narrow backend responsibilities

Retain `DrawList` as the initial rendering boundary.

| Layer | Responsibilities |
|---|---|
| **Core** | Identity, layout, commands, focus, selection, scrolling, scheduling |
| **Platform host** | Windows, input normalization, clipboard, IME/composition, accessibility integration, presentation timing |
| **Renderer** | Textures, glyph resources, batching, buffers, GPU submission |

Metal and OpenGL do not need to know what a `Button` or `ScrollView` is.

Keep room for richer text layout/shaping behind a text-service boundary, without requiring that rewrite now. Measurement, caret positioning, and painting must ultimately share the same text-layout result.

Later, if profiling warrants it, evolve `DrawList` into reusable scene segments. Do not start with retained GPU layers or dirty-rectangle rendering.

## 8. Implementation sequence

| Step | Deliverable | Acceptance criterion |
|---|---|---|
| **1. Establish baseline** | Finish a bounded timing/counter baseline; add opt-in Swift Profile Recorder sampling for Linux/macOS | Reproducible input/render results and a validated stack profile or explicit profiling blocker; allocation profiling is not a gate |
| **2. Prove the lifecycle** | New path for stacks, text, buttons, and fixed-height lists; ordered input without coalescing | Input produces **zero paint calls**; every delivered event is processed in order; stale callbacks remain safe |
| **3. Replace repeated traversal** | Compact nodes, retained layout, modifier lowering, conservative subtree culling | No Block resolution during paint; unchanged measurements reused; no unsafe borrowed lifetimes |
| **4. Fix transcript scaling** | Viewport-driven variable-height virtualization and logical navigation | Scrolling does not scan or measure the entire history; offscreen selection and scroll anchoring survive |
| **5. Migrate real consumers** | Scribe transcript/composer, then Shape Tree and its embedded Scribe UI | Streaming, selection, reveal, commands, and custom text remain correct |
| **6. Optimize measured leftovers** | Boundary invalidation, text caching, scene reuse if needed | Improved p95 latency without unbounded cache growth |

Both consumers pin different Chroma revisions. Migration validation must explicitly point them at the candidate checkout; otherwise passing tests could still exercise the old library.

### Plan of attack

Work through these phases in order, in small runnable changes. Phase 1 records completed baseline work and remaining bounded tasks; later phases are pending. Baseline instrumentation and isolated ownership probes are not a new engine implementation.

The first milestone is **a vertical slice containing a virtual list, button actions, focus navigation, and cached layout**, using the existing `DrawList` and headless tests. Keep the existing path available until the slice passes its correctness and performance checks; do not build a permanent second engine.

#### Phase 1 — Finish a bounded, reproducible baseline

See [storage comparison and baseline status](Benchmarks/StorageComparison/README.md) for historical runs. This revised gate supersedes that report's requirement for allocation profiling and full phase separation before proceeding. The goal is enough evidence to compare the first engine slice—not a complete profiling platform.

Completed evidence:

- [x] Assert content replacement uses the new callbacks rather than require drawing as the mechanism (`replacingContentBeforeInputUsesNewCallbacks`).
- [x] Run core, Examples, and Benchmarks tests before engine changes: 390, 53, and 3 tests passed. The diagnostic follow-up reports 391, 53, and 3 passing tests.
- [x] Capture all 36 release interaction cases with revision/worktree, toolchain, hardware, viewport, item count, and event count. Report installation, cold frame, and warm input/render separately.
- [x] Add fixture counters and opt-in engine diagnostics for body evaluations, registration passes, primitive paint visits, visible lazy-row visits, and focus-array capacity growth. Their scope and timing overhead are documented; these are not allocation counts or fully separated layout/paint stages.
- [x] Compare `Array<Node>` and `UniqueArray<Node>` under equivalent build/update/traversal workloads. Retain Array provisionally; results do not justify adding Swift Collections.

Remaining work, in order:

- [ ] Add an opt-in `ProfileRecorderServer` dependency to the benchmark executable, not the Chroma library. Pin/record the resolved version. Both desktop consumers already have server integration; reuse their configuration pattern rather than create a second profiling service.
- [ ] Add benchmark case selection, diagnostics on/off, and a bounded profile-replay mode. Replay one named workload while sampling; keep UI work on `@MainActor` and allow the server to start/respond independently. Do not leave an infinite workload loop or profiler task running.
- [ ] Add the timeout and cleanup rules below to collection scripts, including dependency resolution, tests, build, metadata commands, benchmark execution, readiness checks, capture, and conversion. Test failure/timeout handling as well as the success path.
- [ ] Collect three fresh, unprofiled trials of a minimum matrix: 1,000 rows, eager/lazy, pointer/scroll/drag, eight events per rendered frame, 400×600 viewport, five warmups and 30 measured frames. Keep instrumentation settings identical across baseline/candidate. Use a separate diagnostic run for detailed counters; expand to 100/5,000 rows only after the minimum matrix completes.
- [ ] Capture one eager and one lazy scroll replay with Swift Profile Recorder, preferably on Linux, using the same workload parameters. Save `.perf` output, request settings, process logs, and the corresponding build metadata. Keep sampling runs separate from latency trials.
- [ ] Inspect profiles for actual stack samples and recognizable Chroma/workload frames. Record unresolved stacks, idle/waiting threads, and sampling overhead limitations; an HTTP success or nonempty file alone is not sufficient validation.
- [ ] Summarize input/render p50/p95, diagnostic work counts, sampled hot paths, and known gaps. Record a profiling/platform blocker explicitly if capture cannot complete under the limits below.

##### Profiler choice and scope

Use [Apple Swift Profile Recorder](https://github.com/apple/swift-profile-recorder) for in-process stack sampling on Linux and macOS. It does not require `sudo`, `CAP_SYS_PTRACE`, or attaching Instruments to the target. Start `ProfileRecorderServer` only when `PROFILE_RECORDER_SERVER_URL_PATTERN` is set, on a per-run local Unix socket; do not expose a public TCP listener.

Build the release executable before starting capture. Preserve symbol information and verify stack quality with the selected toolchain; record any frame-pointer/build flags rather than assume a flag intended for C also configures Swift code. Resolve dependency/API differences against the pinned package version.

Swift Profile Recorder samples running **and waiting** threads. It is not an allocation profiler, exact phase timer, or GPU profiler. Analyze the UI/workload thread separately from profiler/NIO/idle stacks. Do not interpret inclusive stack sample percentages as exclusive CPU time or compare profiled timings with unprofiled timings.

After the instrumented runner is implemented, launch its freshly built binary with:

```sh
PROFILE_RECORDER_SERVER_URL_PATTERN='unix:///tmp/chroma-profile-{PID}.sock' "$bin"
```

The collection wrapper must choose the bounded replay mode and track that process's actual PID; do not select an arbitrary socket by globbing. Wait for `/health` with a deadline, then request a short sample while the selected workload is active. Linux capture commands, for an existing `$socket` and a new `$out` directory (replace `timeout` with the macOS watchdog described below when needed):

```sh
set -eu
curl --fail --silent --show-error --connect-timeout 2 --max-time 20 \
  --unix-socket "$socket" \
  -H 'Content-Type: application/json' \
  --data '{"numberOfSamples":500,"timeInterval":"10ms"}' \
  http://localhost/sample --output "$out/samples.raw.perf"
timeout --signal=TERM --kill-after=5s 30s \
  swift demangle --compact < "$out/samples.raw.perf" > "$out/samples.perf"
```

The sampling request is approximately five seconds; the HTTP timeout includes collection and response work. Retain raw output if conversion fails. Open the validated `.perf` in Speedscope or Firefox Profiler. Do not pipe capture into conversion in a way that masks a failed HTTP request.

##### Timeout and completion policy

These are wall-clock process limits, not performance targets. Enforce them externally as well as using tool-specific duration flags; a requested sample duration does not bound startup, symbolication, or shutdown.

| Operation | Default deadline |
|---|---:|
| Dependency resolution | 5 minutes |
| Each test package | 5 minutes |
| Release build | 10 minutes |
| Each metadata command | 30 seconds |
| Each unprofiled minimum-matrix trial or diagnostic replay | 120 seconds |
| Profiler `/health` readiness | 10 seconds total, at most 2 seconds per request |
| Sampling | 500 samples at 10 ms; HTTP request capped at 20 seconds |
| Demangling/profile validation | 30 seconds each |
| Profile target process, including readiness/capture/conversion | 90 seconds |
| Entire collection attempt | 30 minutes |

- Use GNU `timeout --signal=TERM --kill-after=5s` on Linux; use an available `gtimeout` or a Python process-group watchdog on macOS. Do not assume `timeout` ships with macOS. Make deadlines configurable and record their values.
- On timeout, terminate the owned process group, allow five seconds for cleanup, then force termination of remaining owned children and reap them. Never kill unrelated Swift/app processes by name. Trap interruption/exit to stop the launched target and remove only its socket.
- Stop immediately on test/build failure; never run a stale executable. Resolve its path only after a successful fresh build. Preserve logs and partial artifacts in a new results directory on every exit.
- Record each stage as `passed`, `failed`, `timed-out`, `blocked`, or `not-applicable`, with elapsed time and exit status. Timed-out samples/trials are invalid and must not be included in latency summaries.
- Save hardware/OS, toolchain, resolved dependencies, build flags, workload and instrumentation settings, plus a source snapshot including relevant untracked files. `git diff` alone does not capture new diagnostic sources. Compare only matching configurations on the same platform/hardware.
- Allow at most one targeted retry after an identifiable cause or workload/deadline adjustment. Record changed settings and do not silently mix smaller workloads with earlier baselines. A timeout or unavailable Linux host is a recorded blocker, not an invitation to keep collecting indefinitely.

Allocation profiling is **deferred**, not satisfied by sampling. The failed `xctrace` attach attempts remain invalid evidence; do not repeat them to close this gate. Exact layout/paint separation belongs to the new lifecycle, broader cache/storage coverage to Phase 3, and actual backend/GPU measurements to backend validation. Headless submission cost is `not-applicable`, not zero GPU cost.

**Completion gate:** passing relevant tests, a fresh reproducible minimum timing matrix, a diagnostic work-count run, and either validated sampled profiles or a concise blocker report with retained logs and one concrete follow-up. All owned processes must be stopped. Mark the result `baseline-ready` or `baseline-ready-with-profile-blocker`; the latter permits Phase 2 but does not claim profiling or Linux validation succeeded. Allocation tools and measurements that require the future architecture must not hold Phase 1 open indefinitely.

#### Phase 2 — Prove the new lifecycle in one vertical slice

- [x] Add a minimal single-owner node store with `NodeID(index, generation)`, stable slots, and reuse checks. Test stale handles and keyed row reordering.
- [x] Lower stacks, text, buttons, and a fixed-height virtual list into nodes; keep the existing `DrawList` output.
- [x] Separate build/update, layout, interaction preparation, and paint. Replace registration-through-draw for these primitives.
- [x] Retain a valid interaction snapshot and refresh stale callbacks/geometry without painting. Test content replacement, removed controls, resize, and a modal opening between events.
- [x] Preserve delivered input in one ordered sequence without coalescing, including pointer motion and scroll. Audit both hosts and replace lossy accumulation where necessary.
- [x] Route button activation and keyboard commands through the same action path outside layout/paint; include focus traversal and scope entry/exit.
- [x] Test eight events before one scheduled frame: eight ordered dispatches, zero input-phase paint calls, and no unconditional full rebuild per event.

**Gate:** the slice renders correctly, accepts pointer and keyboard input, and demonstrably removes discarded drawing from input handling.

The slice is opt-in through `HeadlessHost.usesNodeLifecycle` and `WindowRuntime.nodeLifecycleEnabled`. Supported content is stacks, nonselectable text, buttons, command scopes, empty blocks, and `FixedHeightList`; other existing primitives retain the old path. `FixedHeightList` requires the node lifecycle. Observation invalidation refreshes build/layout/preparation before the next event without painting. Eight queued activations produce one scheduled paint and reuse one build (`NodeRuntimeTests`). The slice does not yet provide offscreen logical selection/reveal or granular layout invalidation; those remain later-phase work.

Host audit: Metal captures each event snapshot synchronously before queuing it in `WindowRuntime`; no host change was needed. Wayland now drains ordered pointer/scroll snapshots and one ordered keyboard command/text sequence instead of summed deltas and separate command/text queues. Linux core and host-input tests validate the gate headlessly. Metal compilation and live compositor/GPU presentation are unavailable in this Linux session and remain backend-validation blockers, not claimed successes.

#### Phase 3 — Replace repeated traversal and cache safely

- [ ] Reuse resolved nodes between layout and paint; remove Block resolution and measurement from the paint pass.
- [ ] Retain measurements with explicit validity for content, constraints, and layout environment. Verify changed callbacks update even when identity is unchanged.
- [ ] Fold compatible modifiers into node properties without changing modifier order semantics or focus identity.
- [ ] Separate structural, layout, interaction, and paint invalidation at panel/row boundaries. Test hover, focus, and caret changes without unnecessary layout.
- [ ] Use short-lived spans or `borrowing` / `inout` access for passes; keep graph growth outside active borrows and submitted frame resources independently owned.
- [ ] Prune proven-invisible paint subtrees using effective clips and conservative bounds. Test nested scrolling, overflowing children, overlays, and reversed layouts.
- [ ] Release removed-node callbacks and caches; verify repeated mount/unmount and scrolling do not grow retained memory without bound.

**Gate:** unchanged layout is reused, paint does not evaluate Blocks, and culling does not change visible output or interaction behavior.

#### Phase 4 — Make transcripts scale with the viewport

- [ ] Give virtual lists collection identity/revisions, an ID-to-index lookup, and deferred row builders. Avoid full collection scans on unchanged input frames.
- [ ] Jump directly to fixed-height visible ranges plus overscan, including views far from the start of the collection.
- [ ] Add a variable-height index with estimates and cached measurements; build/measure only required rows and retain an estimated total extent.
- [ ] Preserve item-and-offset scroll anchoring as heights change; test streaming text, insertion above the viewport, width changes, and conditional bottom-following.
- [ ] Preserve offscreen logical selection and implement reveal independently of row instantiation. Test deletion/reordering fallback, scope restoration, and command routing.
- [ ] Keep pointer capture and active editing valid when content is clipped; add tests for dragging out of view and navigating back to a virtualized row.
- [ ] Benchmark 1,000, 100,000, and 1,000,000 fixed-height items plus realistic variable-height transcripts; verify warm work tracks visible/changed content rather than total history.

**Gate:** viewport work remains bounded for unchanged collections, and scrolling/navigation remain stable as rows appear, disappear, or change height.

#### Phase 5 — Migrate real consumers and retire the old path

- [ ] Move remaining built-in primitives and custom-element hooks to the new lifecycle, preserving backend-neutral measurement, interaction preparation, and painting.
- [ ] Point Scribe's desktop package at the candidate Chroma checkout; migrate the transcript, Markdown/text selection, composer, and reveal behavior.
- [ ] Remove application-owned row/layout caches only after Chroma replaces their behavior; move application mutations out of build/paint paths.
- [ ] Point Shape Tree Desktop at the candidate checkout; migrate both its own views and its embedded Scribe UI.
- [ ] Build and run consumer tests against the candidate, not their existing remote pins. Exercise streaming, copy/paste, editing, focus restoration, and modal commands.
- [ ] Validate Metal on macOS and OpenGL/Wayland on Linux, including ordered input and resource lifetime. Record any unavailable platform validation as a blocker.
- [ ] Delete obsolete `Resolved` traversal and registration-through-draw once all callers are migrated; avoid leaving compatibility code on the hot path.

**Gate:** both consumers use the new engine, both backends are validated, and the old execution path is removed.

#### Phase 6 — Optimize only measured remaining costs

- [ ] Re-run the same baseline workloads and compare p50/p95, operation counts, and sampled hot paths. Add regression tests for the improved work counts; collect allocation/retained-memory evidence separately when supported, without treating samples or capacity-growth counts as allocations.
- [ ] Profile actual transcript streaming and input-to-presentation latency, not just synthetic draw-command replay.
- [ ] Add bounded text-layout caching or finer invalidation only where profiles show a remaining cost.
- [ ] Consider reusable scene segments or backend changes only if painting/submission is now a demonstrated bottleneck.
- [ ] Confirm idle windows stop rendering and animations stop requesting frames when inactive.

**Gate:** measured improvements without correctness regressions, input coalescing, or unbounded caches.

### Explicitly deferred

- A new public DSL or broad SwiftUI compatibility.
- A general CSS layout engine or GPUI-style application entity framework.
- Handwritten unsafe arenas, a reference-linked persistent graph, or custom lifetime APIs without demonstrated need.
- Renderer rewrites, retained GPU layers, and dirty-rectangle rendering before profiling justifies them.
- Input-event coalescing; processing every delivered event remains a requirement.

## 9. Baseline validation

Before writing this proposal:

- Release interaction and input-frame benchmarks ran successfully.
- Benchmark and Examples test suites passed.
- The core suite ran **390 tests with one failure**: `replacingContentInvalidatesBeforePointerInput`, reproduced in isolation at [`RegistrationValidityTests.swift:103`](Tests/ChromaTests/RegistrationValidityTests.swift#L103).
- Consumer builds and Wayland runtime behavior were not validated.
- No implementation changes were made; existing work was preserved.

Commands used:

```sh
swift test
swift test --filter RegistrationValidityTests/replacingContentInvalidatesBeforePointerInput
swift test --package-path Benchmarks
swift test --package-path Examples
swift run --package-path Benchmarks -c release InteractionBenchmark
swift run --package-path Benchmarks -c release InputFrameBenchmark
```

These observations describe the inspected working tree, including existing uncommitted benchmark and fixture changes. Recollect baselines before comparing an implementation.

## References

- [Interaction Medium series](https://www.dgtlgrove.com/p/ui-part-1-the-interaction-medium), particularly Parts 2, 7, 8, and 9. Local copy: `/Users/zane/Desktop/interaction-medium`.
- [Clay](https://github.com/nicbarker/clay). Local checkout: `/Users/zane/Developer/clay`.
- [Swift Profile Recorder](https://github.com/apple/swift-profile-recorder): in-process Linux/macOS stack sampling, `ProfileRecorderServer`, `/health`, and `/sample`.
- [Swift Collections](https://github.com/apple/swift-collections), particularly `BasicContainers.UniqueArray` and `RigidArray`; [1.7.1 release notes](https://github.com/apple/swift-collections/releases/tag/1.7.1) and the [`Ref` back-deployment workaround](https://github.com/apple/swift-collections/pull/739).
- [SE-0519: `Ref` and `MutableRef`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0519-ref-mutableref-types.md) and [SE-0447: `Span`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0447-span-access-shared-contiguous-storage.md).
- [GPUI](https://github.com/zed-industries/zed/tree/main/crates/gpui), particularly [`element.rs`](https://github.com/zed-industries/zed/blob/main/crates/gpui/src/element.rs) and [`window.rs`](https://github.com/zed-industries/zed/blob/main/crates/gpui/src/window.rs).

**Target architecture: disposable Blocks, retained layout and interaction, explicit actions, and replaceable renderers.**
