# Chroma

Swift UI library. Metal on macOS 27+; Wayland/EGL/OpenGL ES on Linux.
Swift tools 6.4+; pinned toolchain in `.swift-version`.
Backend targets are selected by platform; no package traits or backend defines are needed.
A shared build plugin embeds Metal/GLSL shader sources, so shaders need no resource bundle.

```sh
swiftly install
swiftly run swift run --package-path Example ChromaDemo
swiftly run swift test
swiftly run swift test --package-path Example
swiftly run swift test --package-path Benchmarks -c release
```

Remote demo (separate terminals):

```sh
swift run --package-path Example -c release RemoteDemoDaemon
swift run --package-path Example -c release RemoteDemoClient
```

Remote connections are unauthenticated; use a trusted connection or protected tunnel.

Benchmarks: `Benchmarks/Scripts/run.sh Benchmarks/results/baseline`.

Bundled font: Noto Sans Mono, SIL OFL 1.1. Distribute the ChromaFont resource
bundle, including [OFL.txt](Sources/ChromaFont/Resources/OFL.txt).
