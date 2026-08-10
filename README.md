# Chroma

UI library written in Swift

⚠️ Unstable: Heavy AI • Active API [dogfooding](https://github.com/zaneenders/scribe)

## Demo

`ChromaDemo` uses the same app state and block tree with either the native backend or the terminal backend.

```sh
# Native Metal window on macOS
swift run ChromaDemo

# Terminal UI
swift run ChromaDemo --terminal
```

Build without the default Metal trait to produce a terminal-only demo:

```sh
swift run --disable-default-traits ChromaDemo
```

