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

Remote demo (separate terminals; rebuild both together):

```sh
swift run --package-path Example -c release RemoteDemoDaemon
swift run --package-path Example -c release RemoteDemoClient
```

Remote connections are unauthenticated: use a trusted connection or protected tunnel.
Benchmarks: `Benchmarks/Scripts/run.sh Benchmarks/results/baseline`.

Bundled font: Noto Sans Mono (SIL OFL 1.1). Distribute the ChromaFont resource bundle,
including [OFL.txt](Sources/ChromaFont/Resources/OFL.txt).
