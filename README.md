# Chroma

UI library written in Swift

⚠️ Unstable: Heavy AI • Active API [dogfooding](https://github.com/zaneenders/scribe)

## Demo

Run the native Metal demo on macOS:

```sh
swift run ChromaDemo
```

Run the Wayland/EGL/OpenGL ES demo on Linux:

```sh
swift run ChromaDemo
```

The native backend is selected by default on each platform. To build the demo
without a graphical backend, use `swift build --disable-default-traits`.
SwiftPM options such as `--traits` must appear before the executable name;
arguments after `ChromaDemo` are passed to the demo itself.

## Fonts

Chroma ships its authored monospaced bitmap display glyphs plus a pre-rasterized
Bedstead readable face in `ChromaFont`. Bedstead is CC0/public-domain dedicated.
Graphical backends build one shared atlas from that bundled data and do not
require HarfBuzz, FreeType, Fontconfig, or an installed system font.
