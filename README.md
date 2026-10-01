# Chroma

⚠️ Work in progress

## Examples

```sh
swift run --package-path Examples PlayDemo
swift run --package-path Examples ChatDemo
swift run --package-path Examples ImageDemo
```

- **Play:** falling blocks with a ghost piece, next-piece queue, scoring, and increasing speed.
  Enter the board with l, then l/Enter to start. d/k move left/right, f rotates, j soft-drops,
  Space drops, P or Escape pauses, and s pauses and leaves the board.
- **Chat:** local, scripted streaming replies, separate conversation drafts, selectable messages,
  and a multiline composer. Enter adds a line; Cmd/Ctrl+Enter sends. Scroll up to read without
  being pulled back; Latest returns to the live reply. Nothing is sent over the network.

- **Image:** a Mandelbrot image demonstrating RGBA rendering and contain scaling.

Each example runs in its own window; there is no shared screen switcher.
Navigate with d/f/j/k, enter groups or use controls with l, and leave with s.
Keys shows navigation shortcuts. Tab and arrows are unbound.
Scores and conversations last for the current app session. The old rendering/font gallery is
retained only as test fixtures.

```sh
swift test --package-path Examples
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
