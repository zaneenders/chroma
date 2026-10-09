# Build a Chroma app

These instructions target main at `7d9012c3` and the APIs in this checkout.
See the [runtime guide](runtime.md) for extension contracts and proposal status.

## Prerequisites

- Swift **6.4**, as specified by [`.swift-version`](../.swift-version) and
  [`Package.swift`](../Package.swift). Install the matching toolchain and check `swift --version`.
- macOS: **27 or newer**, with the matching Apple SDK/toolchain and Metal support.
- Native Linux: a Wayland session (the README's supported compositor is Hyprland),
  EGL/OpenGL ES 3, and development headers/libraries for `wayland-client`,
  `wayland-cursor`, `wayland-egl`, `egl`, `glesv2`, and `xkbcommon`, plus `pkg-config`.
  Wayland headers must include `wl_pointer_listener.warp`; Wayland **1.26** provides it.
  Ubuntu 24.04's stock Wayland headers are too old. Installing `libwayland-dev`
  alone on that release is insufficient.

On Debian/Ubuntu, the other development packages are `libegl1-mesa-dev`,
`libgles2-mesa-dev`, and `libxkbcommon-dev`. A software-rendering setup also needs
`libgl1-mesa-dri` and `xkb-data`. Use a current Wayland development installation;
check which installation `pkg-config` selects before building:

```sh
pkg-config --modversion wayland-client wayland-cursor wayland-egl egl glesv2 xkbcommon
```

The compositor supplies `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR`. Launch native apps
inside that session; setting those variables alone does not create a display.
Headless execution needs no compositor or GPU. A `ChromaApp` executable still links
its native backend even with `--headless`; an executable depending only on `Chroma`
and `ChromaHeadless` and conforming to `HeadlessApp` avoids that dependency.
Root-package `swift test` includes platform backend tests and still needs native build dependencies.

## Minimal counter

Create an empty directory with `Package.swift` and `Sources/Counter/Counter.swift`.
This pins the documented revision so a future API change does not silently alter the example.

`Package.swift`:

```swift
// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "Counter",
  platforms: [.macOS(.v27)],
  dependencies: [
    .package(
      url: "https://github.com/zaneenders/chroma.git",
      revision: "7d9012c3c7de72605f77d3ffce301924365b6192")
  ],
  targets: [
    .executableTarget(
      name: "Counter",
      dependencies: [
        .product(name: "Chroma", package: "chroma"),
        .product(name: "ChromaApp", package: "chroma"),
      ])
  ]
)
```

`Sources/Counter/Counter.swift`:

```swift
import Chroma
import ChromaApp
import Observation

@main
struct Counter: NativeApp {
  @Observable @MainActor final class Model {
    var count = 0
  }
  private let model = Model()

  var body: some Block {
    VStack(spacing: 12) {
      Text("Count: \(model.count)")
      Button("Increment") { model.count += 1 }
    }.padding(16)
  }
}
```

Run from that directory:

```sh
swift build --product Counter
swift run Counter
# Or emit JSONL frames without opening a window:
swift run Counter --headless --viewport 800x600
```

Click **Increment** to change the observed count. EOF or a JSONL `quit` request
(`{"version":1,"op":"quit"}`) ends a headless session.
`App.body` returns a `Block`; there is no separate `Scene` protocol in this revision.
Keep model ownership outside `body`, and perform mutations in actions rather than body evaluation.

For a maintained, larger observable app, see
[`LifeDemo`](https://github.com/zaneenders/chroma-examples/tree/main/Sources/LifeDemo)
and the [examples package](https://github.com/zaneenders/chroma-examples/blob/main/Package.swift).
Run `swift run LifeDemo` from its checkout. The examples have their own Chroma revision
pin; inspect it before using them to validate changes in a neighboring Chroma checkout.

## Contributor checks

Run from the Chroma repository root:

```sh
swift test
swift test --package-path Benchmarks
swift test --package-path HeadlessModeTests
swift format lint --strict --recursive Sources Tests Plugins Tools
swift format lint --strict --recursive Benchmarks/Sources Benchmarks/Tests HeadlessModeTests/Sources HeadlessModeTests/Tests
swift format lint --strict Package.swift Benchmarks/Package.swift HeadlessModeTests/Package.swift
```

The formatter uses [`.swift-format`](../.swift-format). These are local commands;
CI setup is tracked separately in [#101](https://github.com/zaneenders/chroma/issues/101).
See [benchmark checks and profiling](../Benchmarks/README.md),
[headless process tests](../HeadlessModeTests/README.md), and
[app installation](../INSTALLING.md) for their full workflows.

Validation: the sample built with Swift 6.4 on Debian 13 using Wayland 1.26 headers
and a local dependency override to the pinned Chroma source. Its headless smoke check
verified an initial frame, a pointer click changing the count glyph, and clean shutdown
with no stderr. The sample passed the repository's formatter. Remote dependency setup,
macOS compilation, and interactive native window checks were not exercised.
