# Chroma

⚠️ Work in progress

## Demo

```sh
swift run --package-path Example ChromaDemo
```

## Frame scheduling

Chroma owns frame timing. Configure `App.minimumRefreshRate` (default **30 Hz**) and
`App.maximumRefreshRate` (default **60 Hz**); rates must be finite and satisfy
`0 < minimum <= maximum <= 240`.

- Idle content produces no frames.
- Active animations use the minimum cadence without rebuilding content or layout.
- Input and observed state changes request content frames, up to the maximum rate.
- Redraw requests coalesce; input events are processed in order at `.userInitiated`
  priority. Animation work uses `.utility` priority and waits for queued input.
- Every content frame also paints animations and resets the next animation deadline.

Custom animated primitives use `context.animate(into:isActive:_:)` while drawing:

```swift
context.animate(into: &drawList, isActive: isAnimating) { list, frame in
  // Paint using frame.timestamp and captured geometry/state.
}
```

This replaces per-node `requestAnimation` deadlines/rates. Capture layout and observed
state outside the closure where possible; keep paint short, do not register interaction,
mutate state, or nest `animate` calls inside it. An inactive closure paints once and
requests no animation frames. Chroma reuses static commands, clipping, and layout
between content frames; content or viewport changes replace that cache.

Task priority cannot interrupt synchronous main-actor rendering. The cap limits frame
frequency, not the cost of individual frames. Backend/compositor availability can lower
the achieved rate. `HeadlessHost.render()` and `renderAnimations()` are explicit test
steps and bypass automatic rate limiting.

## Inspired by

- Immediate mode UI
- [Interaction medium](https://www.dgtlgrove.com/p/ui-part-1-the-interaction-medium), Ryan Fleury
- SwiftUI
- Vim
