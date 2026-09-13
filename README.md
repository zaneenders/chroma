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

## State and frame lifecycle

Keep application models `@MainActor @Observable`. Chroma tracks properties read
while evaluating and drawing the frame; mutations coalesce into a new frame.
`ScrollViewController` and persistent interaction/text-selection state are also
observable. Frame-local geometry registries and GPU resources are not.

Input is dispatched through the previous completed frame's registrations **before**
tracked rendering. `Button`, `Interactive`, and `TextField` register handlers during
drawing; they do not execute application actions there. Custom controls should pass
an action to `context.buttonState`, not execute an action from `state.clicked`.
`context.textInputState` accepts a live `text: { model.text }` getter and escaping
handlers. Keep custom `body`, measurement, and drawing free of application mutations.
The first frame bootstraps geometry before delivering input. Layout may normalize
scroll offsets and reconcile focus against the newly built geometry.

There is no default refresh floor. A caret's observable clock runs only while editing
without a selection. Continuous animations use Chroma's frame timing instead of
starting their own periodic tasks:

```swift
// Inside a PrimitiveBlock's draw method:
let frame = context.animationFrame(active: !model.isPaused)
let elapsed = frame.timestamp - startTimestamp
// Draw using elapsed time, not a fixed increment per frame.
```

All animated controls in a produced frame receive the same monotonic timestamp
(seconds since system startup). Active calls register next-frame demand, rebuilt on
every draw. Removing or pausing all animated controls stops continuous demand.
Chroma's remote scheduler respects the client's negotiated rate and outstanding
request/backpressure; Wayland follows compositor frame callbacks. There is no
independent animation tick. Headless hosts inspect `needsAnimationFrame` and advance
frames themselves. Paused-time accounting belongs to the animation model; the shared
timestamp itself never pauses. The demo excludes paused intervals from its elapsed time.

Remote wire protocol **v5** adds `waitForFrame`: the client leaves one request pending
until a changed frame is available. A five-second unchanged heartbeat preserves
connection timeout detection without rendering the scene. `requestFrame` remains an
immediate snapshot request. Rebuild both daemon and client together.
