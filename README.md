# Chroma

UI library written in Swift

⚠️ Unstable: Heavy AI • Active API [dogfooding](https://github.com/zaneenders/scribe)

## Demo

Run the native Metal demo on macOS:

```sh
swift run --package-path Example ChromaDemo
```

Run the Wayland/EGL/OpenGL ES demo on Linux:

```sh
swift run --package-path Example ChromaDemo
```

The example is a separate package and selects the native backend for its host
platform. Building it also verifies that Chroma can be consumed through its
public API. To build only the libraries without a graphical backend, run
`swift build --disable-default-traits` from the repository root.

## Fonts

Chroma ships its authored monospaced bitmap display glyphs plus a pre-rasterized
Bedstead readable face in `ChromaFont`. Bedstead is CC0/public-domain dedicated.
Graphical backends build one shared atlas from that bundled data and do not
require HarfBuzz, FreeType, Fontconfig, or an installed system font.
