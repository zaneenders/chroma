# Registration without painting

This change implements the first architecture-handoff milestone: fresh ordered input
through a registration path that does not paint migrated primitives. It deliberately
does not introduce a retained subtree engine or infer validity from stable identity.

## Data flow

Before each actionable event, `WindowRuntime` asks `FrameProducer` to refresh
registration. A fresh `BlockEngine.Resolved` tree reconciles current body values,
measures proposal-dependent sizes, places children, and calls `register(in:context:)`.
The resulting focus tree, hit regions, clipping, scroll layout, command scopes,
current callbacks, and text-editing layout are published together by `endFrame`.
The event is then dispatched once against that update. Passive hover still reuses
the last geometry until presentation; presentation can coalesce without coalescing
actions. Events before the initial frame continue through the existing ordered queue.

Presentation still traverses `draw` with input edges cleared by the scheduled
runtime. Its existing registration side effects remain compatible in this milestone.
Separating presentation effects entirely is follow-up work; this change does not
claim painting is yet a pure read-only operation.

Prepared containers use the same placement arithmetic for registration and drawing.
`Interactive` measures idle content but resolves current-phase content independently
for either traversal, preserving structurally different hover/pressed children.
`TextEditor` owns one immutable text-layout snapshot per update, shared by its pointer
and vertical-motion callbacks and, when painting, its visual commands. Selectable
`Text` likewise shares an immutable `PlainTextLayout` snapshot rather than repeatedly
shaping it for hit tests and selection highlights.

## Cache validity and ownership

| Object | Validity and invalidation | Owner and release |
|---|---|---|
| Resolved body/child values and proposal measurements | One operation only. Reconciled again before actionable input, including unobserved captured values. Proposal is part of measurement lookup. | Local traversal; released on return. No cross-frame subscription or node retention. |
| Text input/selection layout snapshot | Current text, metrics, width, and configuration at registration. Replaced before next actionable event. | Current input-handler/selection registry; replaced during consistent registration update or root reset. |
| Variable-row measurements | Same row measurement identity, width, structural path, theme/font/text scale, and valid observed dependencies. Content assignment or `Row.invalidateMeasurement()` changes identity. | Existing `ScrollViewController` cache; replacing/removing rows releases their measurements and observation subscriptions. Controller disposal releases the cache. |
| Frame observation | One-shot subscription for current presentation generation. Cancellation/rearming and generation checks are unchanged. | `FrameProducer`; previous subscription cancelled on render/reset, stale queued delivery rejected. |

Stable IDs preserve interaction identity; they do not establish that callbacks,
labels, child structure, theme, or intrinsic sizes are unchanged. Callbacks always
reconcile conservatively. Variable-row content whose size depends on unobserved
mutable state must call `invalidateMeasurement()` on that row (or replace `content`).
Observable changes synchronously mark row measurement invalid before asynchronous
redraw delivery, so immediate input cannot use an already-invalid measurement.

No new unbounded persistent cache is introduced. Existing uniform-row identity scans
and lightweight application metadata assembly are unchanged. This work does not
claim every operation is proportional to visible rows.

## Custom primitive migration

`PrimitiveBlock.register(in:context:)` is a source-compatible requirement. Its default
implementation is an explicit legacy adapter that calls `draw` into a temporary list.
It preserves custom primitive behavior, but is counted as both a compatibility
fallback and painting. Declaring `.decorative` is not enough to skip a custom draw:
that method might install commands or mutate ambient context.

A migrated primitive should update current behavior and geometry in `register` and
use `BlockEngine.register` for its children. Like `BlockEngine.draw`, this is a
traversal entry point inside an active runtime frame, not a standalone frame builder.
Use `HeadlessHost.sendInput` and `renderIfNeeded` to exercise the complete update/
dispatch/presentation lifecycle in application tests. Use `BlockContext.registerFocusable`
when a focus leaf is needed without a painted highlight. Reuse placement/context
helpers between `register` and `draw`; do not implement registration by passing a
throwaway drawing sink through the normal paint path. Keep application actions in
registered input callbacks, not measurement or registration. During migration,
existing draw-time input/lifecycle effects must be preserved deliberately and listed
as remaining work.

All built-in primitives, prepared containers/modifiers, command scopes, focus targets,
text controls, and ordinary/virtualized scrolling support the new path. Unmigrated
application primitives still use the adapter, including ShapeTree wrappers until
its companion changes are adopted. A Chroma-only upgrade therefore does not make
all of ShapeTree paint-free.

## Diagnostics and validation

`PipelineMetrics.isEnabled` enables opt-in counters without logging. Snapshot counts
body evaluation, measurement requests/cache hits, assigned-rectangle visits,
registration/paint visits, emitted commands, and compatibility fallbacks by concrete type. Lifetime
gauges distinguish traversal-local resolved nodes from live frame/row subscriptions;
they are not counts of a retained UI tree. Capture includes only objects created
while enabled. `reset()` preserves live gauges; disabling avoids token allocation.

Commands are counted once at the outermost instrumented drawing boundary, including
legacy adapters and navigation painting. Direct writes to unrelated `DrawList`s are
outside the capture boundary. A zero-command count alone is not proof of no painting:
also require zero paint visits and zero compatibility fallbacks.

Regression coverage preserves the existing ordered-input, callback freshness,
initial-frame, input replay, text layout, identity/cancellation, observation lifetime,
frame pacing, and focus-recovery tests. New tests cover paint-free built-in paths,
proposal sharing with operation-scoped lifetime, changed leaf geometry repositioning
siblings, virtualization/clipping, explicit and observed row invalidation, and
current callbacks despite cached variable-row geometry.

See the benchmark README and the measured results accompanying this change for
reproduction commands and platform limitations. Linux tests cannot establish macOS
Metal rendering or subjective ShapeTree application smoothness.
