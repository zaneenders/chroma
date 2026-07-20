```sh 
cd scribe 
scribe --resume F2B4B3FD
```

# Chroma: Needed for a Scribe Frontend

Chroma can already render a clickable, read-only Scribe interface, but it is missing several capabilities required for a practical chat frontend. The main blockers are text input, typography, scrolling, and application-state integration.

## 1. Keyboard, Text Input, and Focus

This is the highest-priority blocker.

`InputState` currently contains pointer and scroll information, while `MetalBackend/InputView.swift` only handles mouse events. Chroma needs:

- Key-down and key-up events
- Edge-triggered key presses
- Modifier-key state
- Text input represented separately from physical keys
- IME and marked-text composition
- Focused-widget tracking
- Tab and shift-tab focus traversal
- Clipboard copy and paste
- Cursor and selection movement
- Keyboard shortcuts

Chroma then needs, at minimum:

- A single-line `TextField`
- A multiline `TextEditor`
- Focus and submit callbacks

Without these features, Scribe cannot provide a prompt editor, keyboard shortcuts, or keyboard-accessible controls.

## 2. A Real Text System

The current text implementation uses a 5x7 ASCII bitmap font:

- `FontMetrics.measure` counts UTF-8 bytes
- `MetalRenderer` generates one glyph per UTF-8 byte
- There is no multiline or wrapping behavior
- Glyphs are restricted to the bitmap atlas

This will not correctly render model output containing Unicode, emoji, smart punctuation, non-English text, or many source-code symbols.

For Scribe, Chroma needs:

- Unicode-capable font shaping and glyph lookup
- System or TrueType font loading
- Multiline measurement
- Word and character wrapping
- Styled runs within a paragraph
- Selectable text
- Caret and range geometry
- Monospace code rendering
- Links and code-block backgrounds

A `RichText` or `AttributedText` primitive would be more useful than constructing every Markdown span as a separate `Text` block.

## 3. Scroll Views and Viewport-Aware Layout

Chroma already has `scrollDelta`, draw-list clip commands, and Metal scissoring, but it does not expose a `ScrollView` or retain scroll position.

A transcript requires:

- A vertical `ScrollView`
- A clipping modifier or clipping container
- Persistent content offset
- Mouse-wheel and trackpad handling
- Stick-to-bottom behavior while streaming
- A scrollbar or position indicator
- Page Up, Page Down, Home, and End navigation
- Scroll-to-item and scroll-to-bottom operations
- Viewport-aware or lazy child construction

Hit testing must also respect clipping. `Interaction.buttonBehavior` currently checks a widget's assigned rectangle without considering whether a scroll container has visually clipped that rectangle. A clipped widget must not receive pointer interaction outside the visible region.

Long Scribe sessions should not lay out and render the entire transcript every frame. Chroma will eventually need an equivalent of `LazyVStack` or another virtualized-list abstraction.

## 4. Better Identity and Retained Interaction State

`WidgetID` exists, but the planned ID stack or `pushID` behavior is not implemented. Buttons currently default to IDs derived from labels.

Dynamic transcript rows, tool calls, queued prompts, and repeated controls need:

- Scoped widget IDs
- Stable IDs for collection children
- An ID stack or `.id(...)` modifier
- Retained state keyed by widget ID
- Focus, selection, and scroll state in addition to hot and active state

Without scoped stable identity, repeated labels and changing collections can collide.

## 5. Logical-Point Rendering and Display Scaling

The original Chroma plan says UI code should operate in logical points and the backend should apply the display's backing scale. The current Metal backend instead lays out against drawable texture dimensions and converts pointer coordinates into drawable pixels.

Chroma should consistently use logical window points, with the renderer responsible for converting points into device pixels. This provides a clean basis for:

- Retina and other display scaling
- User-configurable font sizes
- Accessibility scaling
- Crisp pixel snapping where appropriate
- Layout that does not change with backing scale

## 6. Async Application Integration

Scribe produces streaming events from asynchronous tasks. A prototype can store state in a reference object and update it on `MainActor`, but Chroma should define this integration explicitly.

Needed capabilities include:

- A main-actor application or store model
- Safe state updates from async tasks
- Task lifetime tied to the window or app
- Cancellation when generation is stopped or the window closes
- A render invalidation or wake API if Chroma stops rendering continuously
- App and window lifecycle callbacks

A Scribe frontend must update partial reasoning, answer text, tool progress, usage, errors, and queued messages while an agent run is active.

## 7. Additional Desktop Interaction

After the first prompt-and-transcript frontend works, Scribe will need:

- Right-click and context menus
- Text selection and copying
- Pointer cursor shapes
- File pickers
- Drag and drop
- Image preview and attachment handling
- URL opening
- Window-close handling
- Dialogs and sheets
- Progress indicators and spinners
- Resizable panes

These are not all required for the first prototype, but copyable output and attachment support will become important quickly.

## 8. Linux Backend

`WaylandBackend` is currently a stub. Scribe supports macOS and Linux, while a Chroma frontend would initially be macOS-only.

This is acceptable if the Chroma GUI is an optional macOS frontend and the terminal interface remains cross-platform. If Chroma is intended to replace the terminal frontend across platforms, a functional Wayland backend is a major requirement.

## Existing Chroma Foundation

The existing foundation is useful and should support an initial Scribe frontend:

- Backend-neutral `DrawList`
- Metal rendering with batching and clipping commands
- Declarative `Block` composition
- `VStack`, `HStack`, and `ZStack`
- Padding, frames, backgrounds, and borders
- Pointer capture and buttons
- Per-frame reconstruction from reference-backed application state
- A backend abstraction that keeps Metal out of UI code

The rendering and basic layout foundation does not need to be rewritten before attempting Scribe. Most missing work is concentrated around text, input, scrolling, identity, and application state.

## Work Needed in Scribe Rather Than Chroma

Scribe already exposes much of its agent machinery through `ScribeCore`, including `SessionHarness`, agent events, messages, queues, and tools. However, presentation and persistence functionality remains in `ScribeCLI`, with some of it coupled to Slate:

- Transcript layout and rendering
- Markdown rendering
- Themes and palette
- Configuration loading
- Session loading and persistence
- Profile and session pickers
- Tool-invocation formatting

A new UI-neutral target such as `ScribePresentation` should contain:

- Transcript row and view models
- Markdown-to-styled-runs conversion
- Tool-call presentation
- Configuration and profile loading
- Session discovery and persistence
- Usage and status formatting

Both `ScribeCLI` and a future `ScribeGUI` target could consume this target. Importing `ScribeCLI` directly into the GUI would retain Slate dependencies and terminal-specific assumptions.

## Recommended Vertical Slice

Implement the first usable path in this order:

1. Add keyboard and text events plus focused-widget state to Chroma.
2. Implement a basic multiline `TextEditor`.
3. Add a clipped vertical `ScrollView` with scroll-to-bottom behavior.
4. Replace the ASCII atlas with Unicode-capable font rendering.
5. Add multiline wrapped and styled text.
6. Add a `ScribeGUI` executable depending on `ScribeCore`, Chroma, and `MetalBackend`.
7. Render:
   - A scrollable transcript
   - Streaming assistant text
   - Tool-invocation rows
   - A prompt editor
   - Send and Stop buttons
8. Extract shared presentation and persistence code from `ScribeCLI`.
9. Add selection and copying, Markdown styling, attachments, and session/profile navigation.

## Summary

Chroma can already draw the shell of a Scribe frontend. To make that frontend useful, it primarily needs:

1. A real keyboard, focus, and text-input system
2. Unicode-capable typography with wrapping and styled text
3. Scrollable, clipped, and eventually virtualized content
4. Stable widget identity and retained control state
5. Explicit integration with asynchronous application state
