# Chroma

UI Library in swift

⚠️ Work in progress

## Supported Platforms 

- MacOS (metal)
- Linux (Hyprland OpenGL)
- ... (PRs welcome)

## Examples

The runnable demos in the [chroma-examples](https://github.com/zaneenders/chroma-examples) repository.

## Architecture

Interaction registration and painting are separate phases. Custom leaves implement
`PaintableBlock`; containers implement `LayoutPreparingBlock` and prepare children
for one traversal. Resolved layout and measurement caches are not retained across updates.

## Inspired by

- Immediate mode UI
- [Interaction medium](https://www.dgtlgrove.com/p/ui-part-1-the-interaction-medium) - Ryan Fleury
- SwiftUI
- Vim
