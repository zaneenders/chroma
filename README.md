# Chroma

Swift UI library for macOS 27+ (Metal) and Linux (Wayland/EGL/OpenGL ES).
Requires Swift 6.4+; toolchain pinned in `.swift-version`.

```sh
swiftly install
swiftly run swift run --package-path Example ChromaDemo
swiftly run swift test
swiftly run swift test --package-path Example
swiftly run swift test --package-path Benchmarks -c release
```

Applications run in-process. The framework and demo have no external Swift package
dependencies; the benchmark package has optional profiling dependencies.

Benchmarks: `Benchmarks/Scripts/run.sh Benchmarks/results/baseline`.

Bundled font: Noto Sans Mono (SIL OFL 1.1). Distribute the ChromaFont resource bundle,
including [OFL.txt](Sources/ChromaFont/Resources/OFL.txt).

The demo uses `MetalApp` on macOS or `WaylandApp` on Linux.
Save a scene with Ctrl+Shift+G (defaults to `Example/`), or pass
`--capture-directory EXISTING_WRITABLE_DIRECTORY`.
Clipboard shortcuts are Ctrl+A/C/X/V or Super+A/C/X/V (Omarchy) on Linux,
and Command+A/C/X/V on macOS.
Click a text field before pasting; drag across selectable text to select it.
Scene captures use self-contained version-3 JSON with shared image resources.
Version-2 JSON remains readable; older wire-format captures must be regenerated.

Benchmarks use `--stage cull` (CPU, either platform) or `--stage metal`
(culling plus Metal/GPU timings, macOS). For example:

```sh
swift run --package-path Benchmarks -c release RenderBenchmark --scene text --stage cull
```

Benchmark reports use schema version 4; regenerate baselines rather than comparing
against former wire/pipeline results.

## Move through the interface

The default demo is a local conversation workspace. Switch sessions, leave drafts,
enter messages to save or quote them, and return without losing your place.
The **Render gallery** tab keeps the graphics, font, and virtualized-list examples.

- **MOVE:** `d` left, `f` up, `j` down, `k` right (arrow keys also work).
- **`l`:** enter the selected group, activate a button, or begin editing a field.
- **`s`:** select the containing group. **Escape:** leave EDIT mode for MOVE.
- At an edge, directional navigation searches outward and selects a neighboring
  section without descending into it. Groups remember their selected child.
- History does not follow new messages automatically. **Latest** explicitly moves
  to the bottom; switching sessions preserves drafts and scroll positions.

`Group("Composer") { ... }` defines a navigation boundary without adding layout.
Stacks and visual modifiers do not add navigation levels. `ScrollView("History")`
creates a scroll boundary. Optional names appear in the demo's navigation trail.
