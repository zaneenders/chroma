# Architecture handoff acceptance

This checklist maps the complete [handoff](https://github.com/zaneenders/chroma/blob/ce73c99ae055b6ba1ba75cfcd91f338d91fd539d/CHROMA-ARCHITECTURE-HANDOFF.md) to implementation and evidence. It does not equate headless graph tests with native graphics validation.

## Baseline and integration

- [x] Start from the published fixes. The branch is based on merged Chroma `e46e475`; relevant code matches handoff `6242fe8` / document commit `ce73c99`.
- [x] Preserve subsequent upstream application work. Companion integration follows ShapeTree `4e5432d99687af4714169ee419d344d680d61fc0`, including its Scribe `589b312a952db70b0a06a303bbf035f7e9a86501` dependency and NativeApp entry points.
- [x] Read repository constraints; introduce no `@unchecked`. Native dependencies remain outside core profiling code.
- [x] Final dependency/source receipt and restored production manifests verified against all five imported upstream Git blobs; exact Scribe checkout is clean. Evidence accompanies the companion patch.
- [x] Chroma implementation published and fetched back with an exact tree match. Companion pin instructions identify the final published Chroma revision; ShapeTree publication remains a separate user decision.

## Pipeline responsibilities and preserved behavior

- [x] Fresh bodies, identity, configuration and behavior reconcile before input; measurement performs no actions or focus consumption.
- [x] Prepared containers share proposal results and geometry within an operation; these transient trees are not mislabeled retained trees.
- [x] `register` discovers handlers/geometry without painting migrated primitives. `paint` consumes prepared snapshots without registration or lifecycle effects.
- [x] Custom legacy primitives have an explicit, counted, named adapter. Presentation update captures their combined draw once; painting does not replay its effects.
- [x] Immutable text snapshots have explicit text/column validity and operation ownership, with tests proving sharing across measure/register/paint.
- [x] Interactive measurement remains idle-based, but current-phase children are reconciled and painted, including structural differences.
- [x] Passive hover reuses geometry, frame pacing includes rendering time, and windows return to idle without continuous rendering.
- [x] ShapeTree sidebar retains 30-point uniform rows and 1-point spacing; expensive controls remain virtualized. Full identity/metadata scans are not claimed to be visible-row-only work.
- [x] Focus recovery after virtualization cannot shift the next pointer target.

## Input correctness

- [x] Ordered events are applied once; two captured-count activations before presentation produce two actions.
- [x] Newline then caret movement sees current text layout; registration and presentation never replay input edges.
- [x] Rebuilt release uses current callbacks; replacement/removal cancels press and reinsertion cannot revive it.
- [x] Raw keyboard mappings and pending editing focus are refreshed before resolution; native Wayland session stamps use the new focus state.
- [x] Raw and resolved pre-initial-frame events preserve ordering, including reentrant root replacement.
- [x] Fresh clipping, focus structure, command scopes, copy/select-all providers and hit regions form one consistent update.
- [x] Raw application input handlers run after core input dispatch and before drag-release cleanup, never in painting.
- [x] Stable identity does not imply unchanged callbacks or content. Unobserved layout dependencies have an explicit invalidation contract.

Evidence: existing WindowRuntime, RegistrationRefresh, StructuralInteraction, PointerScrollFocus, FramePacing and text suites; new RawKeyboardFreshness, InputUpdatePhase, ControlPaintIsolation and ScrollPaint suites.

## Persistent geometry validity

- [x] Small opt-in `CachedLayout` / `LayoutCache` boundary retains only sizes and relative placement, not callbacks or block values.
- [x] Fresh behavior can change while known unchanged geometry reuses results.
- [x] Observable builder/measurement changes synchronously invalidate before queued notification delivery; unobserved changes require explicit invalidation.
- [x] Type/path, nested token identity, theme/font/text-scale/hover environment and proposals establish validity. Structural changes cannot inherit unrelated results.
- [x] Changed child size updates dependent parent/sibling geometry; independent sibling boundaries retain valid results.
- [x] Scroll offsets refresh transforms, clipping, visibility and hit regions; variable-row text/content changes invalidate measurement.
- [x] One-shot observations rearm and dispose. Removed boundaries release geometry/subscriptions; replaced roots reject queued stale invalidations.
- [x] UI state is main-actor owned, with checked synchronized validity delivery.
- [x] Explicit bounds cover boundaries, nodes and proposals. Eviction conservatively invalidates the boundary rather than keeping unbounded history.
- [x] No inference of universal paint-only hover or transparent validity for arbitrary closures. Dynamically discovered children outside a sealed boundary remain conservative.

Evidence: RetainedLayoutTests, ScrollRegistrationTests, ObservationLifetimeTests, ObservationDeliveryTests, and resource-release checks in InputUpdatePhase/ScrollPaint.

## ShapeTree boundaries

- [x] All twelve relevant custom primitives support update and pure painting; no measured workspace/sidebar/transcript/picker path falls back to legacy registration painting.
- [x] Ambient BlockContextBridge/workspace state is re-established and restored per operation.
- [x] Viewport registration, command installation, focus/editing transitions, pending reveal, transcript owner/cache/selection-document reconciliation are explicit update work.
- [x] Escape, modal suppression, command-picker actions and selection press/release/drag are ordered input work. Stationary selection autoscroll continues in explicit updates.
- [x] Markdown selection/painting shares a layout only under a complete value key; removed rows are released.
- [x] A real sidebar tool strip adopts the retained boundary with documented observed dependencies and fresh callbacks.

The companion patch contains the application audit, tests and exact dependency instructions. It is intentionally not copied into this repository's core sources.

## Measurement and final evidence

- [x] Counters can be disabled and cover bodies, measurements/cache hits, placement reuse, registration, paint/commands, text layouts, compatibility callers, live nodes and observation subscriptions.
- [x] Final native runs after the last source change: 463 Chroma tests, 13 Wayland tests, and 7 benchmark-package tests pass.
- [x] Latest-baseline ShapeTree symbol-bearing release executable builds against verified local Chroma sources; all 172 optimized desktop tests pass.
- [x] Final comparable release tables include first-frame, active input/presentation, explicit invalidation and idle; timings run without instrumentation or competing builds, counters captured separately.
- [x] Final actual headless application graph workload uses newly built, hash-verified binaries with preserved debug sections; no historical mixed-interaction CPU ratio is claimed.
- [x] Independent final source review and changed-file strict formatting completed; prior correctness findings fixed and all existing assertions preserved.
- [x] Remote-tree verification and exact-commit CI/status lookup completed. No commit statuses or pull-request workflow runs were reported; this is not a CI pass. The final receipt accompanies publication.

See [results](RegistrationResults.md) and the supplied publication/dependency receipts for final evidence. Strict formatting passes changed Swift files; seven unchanged whole-tree lint warnings remain in baseline Metal data fields and UniformRowIdentityTests.

## Explicitly unverified external criteria

- [ ] Interactive native ShapeTree smoothness during scrolling, switching, typing and navigation, plus native idle CPU/GPU behavior.
- [ ] macOS/Metal build, run and profiling evidence.
- [ ] Useful native CPU sampling profile. The permitted Linux `perf` attempt produced metadata but zero samples, so no stack-profile conclusion is drawn.

The Linux executor can compile and test the actual Wayland backend and application. A verified official headless compositor starts its renderer, but Unix-domain socket creation fails with `EPERM`, including the reviewed execution route. `strace`/ptrace is also restricted. No security setting or alternate terminal was used to bypass this restriction. Headless application graph tests and any permitted profiler run do not establish native GUI performance; macOS is unavailable in this Linux task.
