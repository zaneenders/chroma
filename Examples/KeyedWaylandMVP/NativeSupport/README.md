# Native Wayland bridge

This directory documents the opt-in Linux renderer. It does not depend on the old UI/layout runtime.

## Build and run

Use Swift 6.4 and install these packages on a Debian/Ubuntu development machine:

```sh
sudo apt-get install libwayland-dev libegl-dev libgles-dev weston
MVP_NATIVE=1 swift build -c release
MVP_NATIVE=1 swift run -c release keyed-demo
```

Run the app in an existing Wayland session. `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY` select that session. A mouse click activates a control; Tab advances focus, Enter/Space activates, and Escape closes. Text uses the Swift bitmap-font rectangle generator; no font service is involved.

```sh
MVP_NATIVE=1 swift run -c release keyed-demo --frames 120 --screenshot native.ppm
```

The screenshot is an actual `glReadPixels` P6 PPM captured before the final buffer swap, rather than the CPU preview. A nonzero `--frames` count is required to schedule a screenshot. The window minimum is 760 × 640, and the default is 900 × 660.

## Isolated compositor smoke test

```sh
SWIFT=/path/to/swift-6.4/usr/bin/swift scripts/native-smoke.sh
```

This launches headless Weston with its Pixman compositor renderer, while the client uses Mesa's software EGL/GLES renderer. The script builds in `.build-native`, renders twelve compositor-paced frames, validates the screenshot, and shuts down only its own compositor. Logs and the PPM are saved in `.build-native/wayland-smoke`. This requires local Unix-domain sockets to be permitted. It does not use a desktop, GPU device, network listener, or third-party service.

Optional settings:

- `NATIVE_DEPS_ROOT`: a local Debian package extraction root containing `usr/include`, `usr/lib/<multiarch>` and `usr/bin/weston`. The script supplies include/link paths and Weston's module mappings; it changes no system files.
- `WESTON`: path to Weston 14 (the tested version).
- `NATIVE_BUILD_PATH`, `SMOKE_OUT`, and `SMOKE_FRAMES`: build directory, evidence directory, and frame count.

For a restricted, non-root environment, official package archives can be downloaded with `apt-get download` and extracted with `dpkg-deb -x`. A workspace-only apt configuration can place package lists/cache under that workspace while retaining the distribution's signed sources and archive keyring. Do not disable repository signature verification or replace any installed system libraries. Runtime packages providing the unversioned development-library targets are also needed if the system lacks them.

## Boundary and rendering

`WaylandBridge.h` exposes only primitive C values. `wb_run` owns one synchronous Wayland event loop and calls Swift with an input snapshot. Swift completes layout and interaction resolution, then traverses its borrowed draw span. Each `wb_draw_rect` copies primitive values into a fixed C-owned 1,024-quad batch. `wb_flush` uploads the batch synchronously before the Swift draw-span borrow ends. No frame pointer or Swift draw-record pointer is stored by C, and no Swift callback is retained beyond `wb_run`.

The ES2 shader is a deliberately narrow solid rounded-rectangle signed-distance shader. It shares pixel-space conventions with the existing renderer but has no texture atlas, gradient, border, old tree, or old window-runtime dependency. A single VBO is reused, and batches use one upload and one draw each. The host calls `wl_surface.frame` to pace drawing with compositor presentation.

The generated xdg-shell protocol source/header were copied from the existing backend. Their upstream copyright and MIT-style permission notices remain in those files. No existing checkout was modified.

## Deliberate MVP limits

- Input is an accumulated per-frame snapshot. Multiple rapid transitions of one button or key between compositor frames can coalesce; this is not a lossless ordered input stream.
- Keyboard shortcuts use Wayland's physical evdev key codes. General text input, keyboard layout translation, repeat, IME, clipboard, touch and cursor themes are not implemented.
- The C bridge forwards wheel deltas, but the demo currently has no scroll widget.
- Redraw continues while visible, including when idle. Damage tracking and idle suspension are not implemented.
- One window, integer surface-pixel coordinates, no fractional scaling or HiDPI buffer scaling, and no accessibility bridge.
- The smoke script exercises real presentation and GPU readback; it does not inject compositor input or claim pointer/keyboard integration coverage.

## Renderer-only smoke and listener unit tests

Where an executor forbids Unix-domain sockets, this distinct test can still exercise the same GLSL, VBO batching and GPU readback through Mesa EGL surfaceless:

```sh
scripts/native-smoke.sh --egl
# Or, after a native build:
MVP_NATIVE=1 swift run -c release keyed-demo --egl-smoke --frames 12 --screenshot egl.ppm
```

This is **not** Wayland presentation coverage. The `--egl-smoke` mode uses a pbuffer and prints that distinction in its result.

Production listener-to-snapshot translation and real EGL alpha/batch behavior can be checked without a compositor:

```sh
for test in input render; do
  cc -DWB_NATIVE -ISources/WaylandBridge/include \
    NativeSupport/bridge-${test}-test.c Sources/WaylandBridge/xdg-shell-protocol.c \
    $(pkg-config --cflags --libs wayland-client wayland-egl egl glesv2) -lm \
    -o /tmp/keyed-bridge-${test}-test
  LIBGL_ALWAYS_SOFTWARE=1 /tmp/keyed-bridge-${test}-test
done
```

These are synthetic calls into the production pointer/keyboard listeners. They verify coordinates, button edges, duplicate-press suppression, wheel accumulation, shortcuts, focus leave, and drag cancellation on pointer leave. They do not prove compositor delivery. The separate renderer test reads back RGBA to assert correct half-alpha composition over an opaque clear, fully opaque antialiased edges, and fixed-batch rollover after 1,025 quads.

## Verification in the implementation environment

- Swift 6.4 native release build: passed.
- C bridge `-Wall -Wextra -Werror` syntax check: passed.
- Production input-listener unit tests: passed.
- Actual EGL alpha and 1,025-quad batch-rollover assertions: passed. Separate RGB/alpha blend factors preserve the opaque window alpha through translucent/antialiased draws.
- Integrated Swift-to-EGL renderer: twelve 900 × 660 frames passed on llvmpipe (LLVM 19.1.7), OpenGL ES 3.2, Mesa 25.0.7. GPU readback produced a valid 1,782,015-byte PPM with 65 distinct colors, visually reviewed for labels, cards, spacing, and rounded corners.
- Weston 14 headless launch: backend initialization passed; socket creation blocked by this executor. An isolated `socket(AF_UNIX, SOCK_STREAM)` diagnostic returned `EPERM`, including through the available escalation flow. Actual Wayland presentation, live resizing, and compositor-delivered input remain unverified here. The default smoke script is provided for a normal Linux development environment.
