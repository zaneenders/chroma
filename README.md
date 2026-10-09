# Chroma

UI Library in swift

⚠️ Work in progress 🤖

## Supported Platforms 

- MacOS (Metal)
- Linux (Hyprland OpenGL)
- ... (PRs welcome)

## Examples

Runnable CPU examples live in `HeadlessModeTests/Sources`. The separate
[chroma-examples](https://github.com/zaneenders/chroma-examples) repository needs
migration when adopting this breaking direct-construction API.

```swift
import Chroma
import ChromaHeadless

@main struct Demo: HeadlessApp {
  func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    buffer.text(Text("Hello"), context: context.keyed("greeting"))
  }
}
```

## Runtime and CPU-only development

Direct construction writes typed nodes into one reusable, integer-handle layout buffer.
See [runtime and migration](RUNTIME.md) for the small public API and freshness rules.

Run CPU-side tests without Metal/Wayland development dependencies:

```sh
CHROMA_HEADLESS_ONLY=1 swift test -j 2
```

This omits native backend and ChromaApp products for that SwiftPM invocation.
Use the same environment setting for dependency resolution, builds and tests;
unset it for the normal package. SwiftPM replans when the manifest environment changes.

## Installing apps

Run `swift package chroma-install` from the app package. Builds release with symbols;
add `--without-profiling` to omit debug info. See [Install](INSTALLING.md).

## Inspired by

- Immediate mode UI
- [Interaction medium](https://www.dgtlgrove.com/p/ui-part-1-the-interaction-medium) - Ryan Fleury
- SwiftUI
- Vim
