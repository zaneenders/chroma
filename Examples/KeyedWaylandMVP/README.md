# Keyed Wayland MVP

Small standalone Swift 6.4 experiment. Persistent keyed slots retain interaction/animation state; a noncopyable owner gives a nonescaping build scope and lifetime-bound draw view. Row/column construction is direct, without result builders. Geometry and callbacks are refreshed before input dispatch.

Status: early draft, implementation and validation still in progress. The debug executable now compiles. A Swift 6.4 compiler LLVM verification failure was avoided by making stored helper record types internal rather than private. Native dependencies and actual Wayland launch are still being verified. Do not yet treat this as a production backend or a complete runtime replacement.

The demo is isolated from Chroma's existing layout/runtime. Its native bridge adapts the existing Wayland xdg protocol support and rounded-quad shader boundary. Text is a tiny bitmap font expanded into quads. No editor, Markdown, accessibility, text shaping, full flex layout, or production resource scheduling is implemented.

Requires Swift 6.4 with the experimental `Lifetimes` feature (enabled in Package.swift). Intended CPU commands:

```sh
swift test
swift run keyed-demo --cpu --screenshot preview.ppm
swift run -c release keyed-demo --benchmark --frames 10000
```

Intended Linux native command, after installing Wayland/EGL/GLES development packages:

```sh
MVP_NATIVE=1 swift run keyed-demo
```

Frame storage must be consumed synchronously: GPU work may continue only after the backend has copied/uploaded the data. The frame arena is never passed as an asynchronous retained pointer. `~Copyable`/`~Escapable` express ownership and lifetime constraints; they do not promise zero allocations for strings, captures, dictionaries, or output construction.
