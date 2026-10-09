# Virtualized scroll metadata retention

This diagnostic measures retained entry counts, not allocator bytes, process RSS,
frame latency, or native rendering performance.

## Fixture and results

Swift 6.4 / Linux x86_64, debug test build. Baseline:
`7d9012c3c7de72605f77d3ffce301924365b6192`.

The `ScrollMetadataTests` fixture uses 10,000 uniform rows, a 20-point row height,
and a 200 × 100 viewport. It selects a control, steps out, then makes 1,000
180-point scroll jumps. The final offset is 180,000 points. The two-control
variant nests a button inside a vertical stack alongside a second button in a horizontal stack.
After scrolling, step-in restores the exact remembered leaf.

| Fixture | Baseline rectangles / keys | Fixed rectangles / keys |
| --- | ---: | ---: |
| Simple leaf, remembered row | 7,007 / 7,007 | 8 / 8 |
| Two nested controls per row, remembered control | 14,014 / 14,014 | 15 / 15 |
| Registration-only scroll, no remembered control | Not measured | 7 / 7 |

The baseline fails both long-scroll bounded-growth assertions while restoration
still succeeds. Fixed counts are asserted exactly by the regression tests.
Registration-only coverage delivers real scroll inputs before each fresh
registration; it does not rely on controller requests, which that phase defers.

The bound is the current registered leaves (including overscan) plus at most one
remembered and one pending leaf per scroll. Pruning occurs after reconciliation,
so existing input/navigation paths can still use the preceding registration.
When a logical row is registered again, controls no longer present in that row
are discarded even if they used to be remembered or pending. Layout changes
continue to invalidate old geometry, and removing/resetting a scroll releases its
metadata. The temporary membership sets are cleared before registrations publish.

This bounds `ScrollState.rows` and `rowKeys`; it does not claim that every
persistent navigation structure or collection identity snapshot is viewport-sized.
No row bodies, callbacks, or prepared layouts are cached by this change.

## Reproduction

From the repository root with Swift 6.4 and the platform dependencies installed:

```sh
swift test --filter ScrollMetadataTests
swift test
swift format lint --strict \
  Sources/Chroma/Interaction/Interaction.swift \
  Sources/Chroma/Interaction/ScrollInteraction.swift \
  Tests/ChromaTests/ScrollMetadataTests.swift
```

The full fixed root suite passed 554 tests: 485 core, 23 Markdown, 16 Wayland,
19 installer, and 11 headless. Coverage includes logical Up/Down, removal and
identity changes, remembered restoration, pending focus/reveal, scroll offsets,
callback freshness, and registration/painting isolation. Six metadata tests cover seven cases,
including two parameterized long-scroll variants and explicit pin, lifecycle,
content-replacement, and registration-only regressions.

Native macOS/Metal and interactive display testing were not run. There are no
wall-clock regression thresholds or speedup claims.
