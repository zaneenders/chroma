# Chroma

UI Library in swift

⚠️ Work in progress 🤖

## Supported Platforms 

- MacOS (Metal)
- Linux (Hyprland OpenGL)
- ... (PRs welcome)

## Rendering

`DrawQuad` is the drawable primitive. Its normalized `sourceRect`, texture, corner
colors, corner radii, border thickness, and edge softness compose independently.
A zero border thickness fills the quad; positive thickness produces an inward
border. Edge softness is measured in logical pixels, with antialiasing retained
at zero.

Append custom quads with `DrawList.append(_:)`. The shape, text, and image helpers
lower to quads; text emits one quad per grapheme using the bundled glyph atlas.
`DrawEntry` contains only quads and ordered clip push/pop entries.

This replaces `DrawCommand` without compatibility aliases. Headless frame payloads
now contain quads and texture coordinates rather than text strings or shape cases.

## Examples

The runnable demos in the [chroma-examples](https://github.com/zaneenders/chroma-examples) repository.

## Inspired by

- Immediate mode UI
- [Interaction medium](https://www.dgtlgrove.com/p/ui-part-1-the-interaction-medium) - Ryan Fleury
- SwiftUI
- Vim
