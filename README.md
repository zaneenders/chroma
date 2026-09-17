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
dependencies in their targets. The installer uses `swift-subprocess`; the benchmark
package has optional profiling dependencies.

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

## Install an app

From this checkout, start guided setup without a configuration file:

```sh
swift run chroma-install
```

Choose `Example` as the package directory to install ChromaDemo. The installer
lists executable products, asks for app metadata and installation options, then
builds and installs after confirmation. Quit an existing app before reinstalling.
After a successful install it offers to save `chroma-config.json` in the selected
package directory, asking before replacing an existing config.

Replay a saved config interactively, or accept its choices without prompting:

```sh
swift run chroma-install Example/chroma-config.json
swift run chroma-install Example/chroma-config.json --yes
swift run chroma-install Example/chroma-config.json --prefix "$HOME/.local" --yes
```

From another app repository with a sibling Chroma checkout:

```sh
swift run --package-path ../chroma chroma-install ./chroma-config.json
```

Run `swift run chroma-install --help` for overrides. Config paths are relative to
its containing directory; `~` is expanded at runtime. The generated version-1
config records product, display name, app identifier, package path, configuration,
Linux prefix, macOS destination, and signing identity reference (not credentials).
Without a terminal, a config and `--yes` are required. Noninteractive overrides do
not rewrite the config. SwiftPM evaluates the selected package's manifest and
build tools, so only install packages you trust.

Linux defaults to `~/.local`: the executable and SwiftPM resources go in
`lib/APP_IDENTIFIER`, a launcher in `bin/PRODUCT`, and a desktop entry in
`share/applications`. Add `~/.local/bin` to PATH for terminal launch. Builds use
the native engine and static Swift runtime; native Wayland/EGL/GLES/xkbcommon
libraries and their development files are still required. Prefixes support
letters, digits, spaces, `/`, `.`, `_`, and `-`.

macOS defaults to `~/Applications/PRODUCT.app`. Bundles include SwiftPM resources
and are signed and verified before installation. The default ad-hoc signature
(`-`) is for local use; choose a stable signing identity for apps needing Keychain
or permission continuity. This is not notarized distribution. macOS installation
still needs validation on a Mac.

Installation stages files, refuses unrelated destinations and symlinked install
paths, and rolls back replacements on failure. It does not elevate privileges or
modify application data. Installed ChromaDemo captures use the user's application
support directory under `ChromaDemo/Captures`, rather than the source checkout.
Custom icons, app-specific plist/entitlement configuration, uninstall, and archive
packaging are not yet supported.
