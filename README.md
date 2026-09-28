# Chroma

⚠️ Work in progress

UI framework where keyboard interactions are first class. Supports macOS 27+ (Metal) and Linux (Wayland/EGL/OpenGL ES). Requires Swift 6.4+; toolchain pinned in `.swift-version`.

## Demo

```sh
swiftly install
swiftly run swift run --package-path Example ChromaDemo
swiftly run swift test
swiftly run swift test --package-path Example
swiftly run swift test --package-path Benchmarks -c release
```

Applications run in-process. The framework and demo have no external Swift package dependencies; the benchmark package depends only on Chroma.

The demo uses `MacOSApp` on macOS or `WaylandApp` on Linux.
Save a scene with Ctrl+Shift+G (defaults to `Example/`), or pass
`--capture-directory EXISTING_WRITABLE_DIRECTORY`.
Clipboard shortcuts are Ctrl+A/C/X/V or Super+A/C/X/V (Omarchy) on Linux,
and Command+A/C/X/V on macOS.
Click a text field before pasting; drag across selectable text to select it.
Scene captures use self-contained version-3 JSON with shared image resources.
Older capture formats must be regenerated.

## Benchmarks

Benchmarks: `Benchmarks/Scripts/run.sh Benchmarks/results/baseline`.

Use `--stage cull` (CPU, either platform) or `--stage metal`
(culling plus Metal/GPU timings, macOS). For example:

```sh
swift run --package-path Benchmarks -c release RenderBenchmark --scene text --stage cull
```

Benchmark reports use schema version 5; regenerate baselines rather than comparing
against former wire/pipeline results.

Bundled font: Noto Sans Mono (SIL OFL 1.1). Distribute the ChromaFont resource bundle,
including [OFL.txt](Sources/ChromaFont/Resources/OFL.txt).

## Inspired by

- Immediate mode UI
- Interaction medium, Ryan Fleury
- SwiftUI
- Vim
