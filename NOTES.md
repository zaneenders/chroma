# macOS vs. Linux Backend Review Notes

## Summary

The backend architecture is moving in a good direction:

- Metal and Wayland consume backend-neutral `DrawList` commands.
- `App.run(on:)` centralizes content, title, refresh rate, and key-binding setup.
- Window sizing uses the backend-neutral `Size` type.
- `BackendError` provides a shared error vocabulary.
- Linux-only system-library declarations avoid probing Wayland dependencies on macOS.
- Wayland now waits for its initial configure event and uses a poll-based event loop instead of drawing after every dispatch.

The main concern is that the current API suggests Metal/Wayland parity without guaranteeing feature parity. The backend contract should explicitly cover lifecycle, errors, input, clipboard support, viewport scaling, rendering capabilities, redraw scheduling, and close behavior.

## Findings

### 1. High: Linux has no keyboard, text-input, or clipboard integration

`App.run(on:)` passes the app's key bindings through `Renderer.setKeyBindings`, but `WaylandRenderer` does not implement that method. It silently receives the protocol's no-op default.

Relevant code:

- `Sources/Chroma/Renderer.swift:14`
- `Sources/Chroma/Renderer.swift:20`
- `Sources/WaylandBackend/WaylandRenderer.swift:73`
- `Sources/WaylandBackend/WaylandRenderer.swift:236`
- `Sources/WaylandBackend/InputAccumulator.swift:21`

The Wayland seat listener only creates a `wl_pointer`; it never creates a `wl_keyboard`. `InputAccumulator` only produces pointer and scroll input, so `InputState.commands` and `textEvents` are always empty.

Consequences on Linux:

- Navigation key bindings do nothing.
- Text fields cannot receive keyboard input.
- Copy/paste and selection shortcuts do nothing.
- The demo advertises controls that are unavailable.
- The no-op `setKeyBindings` makes the backend appear API-compatible when it is not.

Recommended work:

- Add `wl_keyboard` seat handling.
- Use `xkbcommon` for keymaps, modifiers, compose, and repeat.
- Add a Wayland equivalent of `ChromaInputView.handlePlatformCommand`.
- Add clipboard/data-device support for copy and paste.
- Implement `WaylandRenderer.setKeyBindings(_:)`.
- Consider a shared backend-neutral key-command resolver to prevent platform drift.

### 2. High: Wayland shader failures terminate the process

Most Metal initialization failures become `BackendError.initializationFailed`, but Wayland shader compilation and linking use `fatalError`.

Relevant code:

- `Sources/WaylandBackend/WaylandRenderer.swift:404`
- `Sources/WaylandBackend/WaylandRenderer.swift:423`
- `Sources/WaylandBackend/WaylandRenderer.swift:428`
- `Sources/WaylandBackend/WaylandRenderer.swift:440`

A GLSL or driver failure therefore crashes the application and bypasses the throwing `run()` API.

Recommended work:

- Make `compileShader` throwing.
- Include shader compiler and linker logs in the error.
- Convert setup failures to `BackendError`, for example:

```swift
throw BackendError.initializationFailed(
  backend: "Wayland",
  stage: "vertex shader",
  reason: message
)
```

- Remove the private `WaylandError`, or only use it internally before mapping it to `BackendError`.

### 3. Medium-high: The Linux demo ignores the configured window size

`ChromaDemo` declares a `960 x 640` window. `WaylandApp.main()` correctly passes `app.windowSize`, but the demo's custom entry point constructs `WaylandRenderer()` with its `800 x 600` default.

Relevant code:

- `Sources/ChromaDemo/ChromaDemo.swift:13`
- `Sources/ChromaDemo/ChromaDemo.swift:24`
- `Sources/WaylandBackend/WaylandApp.swift:11`

Fix:

```swift
try app.run(on: WaylandRenderer(size: app.windowSize))
```

Longer term, avoid duplicating backend startup logic between `MetalApp`, `WaylandApp`, and `ChromaDemo`.

### 4. Medium-high: Metal and Wayland have inconsistent initialization lifecycles

Metal creates its device, shaders, pipelines, and fonts in a throwing initializer:

```swift
let renderer = try MetalRenderer(size: app.windowSize)
```

Wayland has a nonthrowing initializer and postpones meaningful setup until `run()`:

```swift
let renderer = WaylandRenderer(size: app.windowSize)
try renderer.run(...)
```

Relevant code:

- `Sources/MetalBackend/MetalRenderer.swift:41`
- `Sources/MetalBackend/MetalRenderer.swift:108`
- `Sources/WaylandBackend/WaylandRenderer.swift:68`
- `Sources/WaylandBackend/WaylandRenderer.swift:77`

Recommended work: choose one lifecycle contract for graphical backends.

Options:

1. Use throwing initializers that establish all resources possible before entering the event loop.
2. Keep initializers lightweight and use a shared explicit `start`/`run` lifecycle.

Wayland cannot complete surface initialization before configure events, but connection and registry setup can still follow a consistent factory or lifecycle-state API.

### 5. Medium: Backend selection and startup are duplicated

There are three startup paths:

- `MetalApp.main()`
- `WaylandApp.main()`
- `ChromaDemo.main()`

The demo has already drifted from `WaylandApp` by losing `windowSize`. Conditional imports and renderer selection are repeated as well.

Relevant code:

- `Sources/MetalBackend/MetalApp.swift`
- `Sources/WaylandBackend/WaylandApp.swift`
- `Sources/ChromaDemo/ChromaDemo.swift:4-29`

Recommended work: introduce one backend-selection layer, such as:

```swift
public protocol AppBackend {
  @MainActor
  static func run<A: App>(_ app: A) throws
}
```

Another option is a platform facade product that selects the enabled native backend. The demo should use the same entry-point mechanism as downstream applications.

If separate `MetalApp` and `WaylandApp` protocols remain, add API-parity tests that run the same app through each entry point.

### 6. Medium: Wayland does not implement the complete `DrawCommand` contract

Rounded rectangles are deliberately rendered as square rectangles.

Relevant code:

- `Sources/WaylandBackend/WaylandRenderer.swift:546`
- `Sources/WaylandBackend/WaylandRenderer.swift:550`

This creates visible semantic differences for surfaces, borders, buttons, and modals rather than merely an optimization difference.

Recommended work:

- Implement rounded-rectangle rendering in GLES, or
- Formally expose backend capabilities so Chroma can avoid unsupported commands.

Add backend-neutral conformance tests that feed each renderer a canonical `DrawList` containing every command case.

### 7. Medium: The package manifest is asymmetric and host-dependent

`MetalBackend` is declared unconditionally as a product and target. `WaylandBackend` only exists when the manifest is evaluated on Linux.

Relevant code:

- `Package.swift:3-9`
- `Package.swift:25-40`
- `Package.swift:58-75`
- `Package.swift:77-138`

Effects:

- Linux still has `MetalBackend` as the default trait even though Metal is macOS-only.
- On macOS, `swift package dump-package` contains the Wayland trait but not the Wayland product.
- Consumers see different product graphs depending on the host.
- Host-dependent declarations can complicate IDE metadata, documentation, dependency resolution, API inspection, and cross-compilation.

The current setup does have the benefit of avoiding Wayland `pkg-config` probes on macOS.

Recommended work:

- Prefer platform-conditional dependencies while retaining a consistent package shape, if SwiftPM supports the required system-library behavior.
- If host-conditional declarations are necessary, document them explicitly.
- Reconsider making `MetalBackend` the global default trait.
- Remove `METAL_TRAIT` if it is no longer used.

### 8. Medium: `Renderer` is package-scoped

The core renderer abstraction is package-only:

```swift
@MainActor
package protocol Renderer: AnyObject
```

Relevant code:

- `Sources/Chroma/Renderer.swift:2`

This works for first-party Metal, Wayland, and Headless targets, but a backend in another Swift package cannot conform. Consumers also cannot call `App.run(on:)`, because it is package-scoped.

This is fine if Chroma intentionally supports only first-party backends. It becomes a blocker if Linux is the start of a pluggable architecture for X11, Windows, Vulkan, browsers, or custom compositors.

Recommended work: decide the extension policy now. If external backends are a goal, expose a small public backend protocol while retaining low-level details internally. A public `AppBackend` entry point may be safer than exposing the entire existing `Renderer` protocol.

### 9. Medium-low: Wayland lacks output-scale and fractional-scale handling

Wayland uses the logical `xdg_toplevel` dimensions directly as the EGL window and framebuffer dimensions. There is no `wl_surface_set_buffer_scale`, output tracking, or fractional-scale protocol integration.

Relevant code:

- `Sources/WaylandBackend/WaylandRenderer.swift:337-346`
- `Sources/WaylandBackend/WaylandRenderer.swift:393-401`
- `Sources/WaylandBackend/WaylandRenderer.swift:509-535`

This can produce blurry rendering or incorrect density on high-DPI displays compared with Metal.

Recommended work: separate these concepts:

- Logical viewport size used by Chroma layout and input.
- Physical framebuffer size used by EGL and `glViewport`.
- Scale used for rendering and scissor rectangles.

A shared backend viewport model would help Metal and Wayland use the same coordinate semantics.

### 10. Medium-low: Public `run()` defaults contain an old demo title

Both renderers expose:

```swift
run(title: String = "Hello Triangle")
```

Relevant code:

- `Sources/MetalBackend/MetalRenderer.swift:126`
- `Sources/WaylandBackend/WaylandRenderer.swift:77`

The protocol requires an explicit title, and `App.run` always supplies one, so the defaults are unnecessary and appear left over from an earlier sample.

Recommended work: remove the defaults or use a neutral value such as `"Chroma"`.

### 11. Medium-low: Wayland cleanup is incomplete and not state-safe

Wayland cleanup deletes textures and the GL program, but not:

- `vao`
- `quadVBO`
- `instanceVBO`

It also leaves stored pointers and GL IDs non-nil/nonzero after destruction.

Relevant code:

- `Sources/WaylandBackend/WaylandRenderer.swift:661-684`

This is mostly harmless for one process-lifetime run, but the public API does not document the renderer as single-use. Re-running after cleanup or partial setup could be unsafe.

Recommended work:

- Delete all GL resources.
- Reset handles after destruction.
- Use `defer { cleanup() }` in `run()` to consolidate cleanup.
- Explicitly model the renderer as single-use, or reset `running`, `configured`, and all native state before another run.

## Proposed backend contract

The shared backend API should explicitly define:

1. Initialization and event-loop lifecycle.
2. Error mapping and recoverability.
3. Keyboard, pointer, text-input, and clipboard capabilities.
4. Logical viewport versus physical framebuffer dimensions.
5. Required support for every `DrawCommand` case.
6. Redraw scheduling and minimum refresh-rate semantics.
7. Close callback semantics.
8. Whether renderers are single-use.
9. Whether external packages may provide backends.

## Suggested implementation order

1. Replace Wayland `fatalError` paths with `BackendError`.
2. Fix `ChromaDemo` to pass `app.windowSize` to `WaylandRenderer`.
3. Implement or explicitly gate Wayland keyboard, text-input, and clipboard support.
4. Consolidate backend startup to remove duplicated `main()` logic.
5. Add Linux CI that builds and tests with `--traits WaylandBackend`.
6. Add shared backend contract and `DrawCommand` conformance tests.
7. Add DPI scaling and rounded-rectangle parity.
8. Decide whether third-party backend conformance is a supported API goal.

## Validation performed during review

- Reviewed the `main...wayland` changes and current backend implementations.
- Ran `swift test` on macOS: **99 tests in 12 suites passed**.
- Ran `git diff --check`: no whitespace errors.
- Verified the package manifest as evaluated on macOS.
- The Wayland target could not be compiled or exercised from the macOS review environment; Linux compile/runtime behavior still needs CI or Linux-host validation.
