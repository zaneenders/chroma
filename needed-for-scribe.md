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
