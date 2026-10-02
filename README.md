# Chroma

UI Library in swift

⚠️ Work in progress

## Supported Platforms 

- MacOS (metal)
- Linux (Hyprland OpenGL)
- ... (PRs welcome)

## Examples

The runnable demos in the [chroma-examples](https://github.com/zaneenders/chroma-examples) repository.

## Headless mode

[Headless agents](Documentation/HeadlessAgents.md) describes running an App without a window, controlling it with JSONL over stdin, and inspecting draw commands and focus state on stdout.

## Architecture

[Registration without painting](Documentation/RegistrationPipeline.md) describes the input-update path, cache validity, and custom primitive migration.

## Inspired by

- Immediate mode UI
- [Interaction medium](https://www.dgtlgrove.com/p/ui-part-1-the-interaction-medium) - Ryan Fleury
- SwiftUI
- Vim
