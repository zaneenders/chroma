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
swift run --traits WaylandBackend ChromaDemo
```

SwiftPM options such as `--traits` must appear before the executable name;
arguments after `ChromaDemo` are passed to the demo itself.
