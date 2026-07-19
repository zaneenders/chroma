# Immediate-Mode GUI Refactor Plan

```sh
scribe --resume E5A8D0A5-46FE-4E01-870E-3334A4865232
```

## Current State

The current `macos` branch is a small Metal demo that builds successfully with `swift build`.

Its responsibilities are tightly coupled:

- `HelloTriangel.swift`: AppKit application/window setup and keyboard input
- `Renderer.swift`: Metal setup, shaders, demo state, geometry generation, text generation, and command encoding
- `FontAtlas.swift`: bitmap font data and Metal texture creation

The main refactor is to separate immediate-mode UI construction from GPU rendering. Application code should describe the entire interface every frame, while the GUI context retains only interaction state such as the active and focused widgets.

## Target API

A first usable API could look like this:

```swift
final class DemoState {
  var count = 0
}

func buildUI(_ ui: inout UIContext, state: DemoState) {
  ui.beginFrame()

  ui.beginPanel(
    "controls",
    rect: Rect(x: 20, y: 20, width: 260, height: 180)
  )

  ui.label("Immediate Mode GUI")

  if ui.button("Increment") {
    state.count += 1
  }

  ui.label("Count: \(state.count)")

  ui.endPanel()
  ui.endFrame()
}
```

The intended flow is:

1. AppKit events update an `InputState`.
2. Every frame, application code calls widgets such as `button` and `label`.
3. Widgets immediately calculate layout and interaction.
4. Widgets append primitive drawing commands to a `DrawList`.
5. Metal consumes the completed draw list without knowing about buttons, panels, or other widgets.

## Target Architecture

```text
AppKit events
     │
     ▼
 InputState
     │
     ▼
 UIContext ─────── Application state
     │
     ├── ID generation
     ├── hot/active/focused widget state
     ├── layout stack
     └── clipping stack
     │
     ▼
 DrawList
     │
     ├── solid rectangles
     ├── borders
     ├── text
     └── clip commands
     │
     ▼
 MetalRenderer
```

This creates two reusable layers:

- **Rendering layer:** immediate drawing commands such as `fillRect` and `text`
- **GUI layer:** widgets such as `button`, `label`, and `panel`

The Metal renderer should not contain button logic, and widgets should not create Metal buffers directly.

## Suggested Source Layout

```text
Sources/
  ImmediateGUI/
    Geometry.swift
    Color.swift
    InputState.swift
    DrawCommand.swift
    DrawList.swift
    UIContext.swift
    WidgetID.swift
    Layout.swift
    Theme.swift
    Widgets/
      Label.swift
      Button.swift
      Panel.swift

  MetalBackend/
    MetalRenderer.swift
    MetalResources.swift
    FontAtlas.swift
    Shaders.metal

  Demo/
    DemoApp.swift
    DemoState.swift
    DemoUI.swift

Tests/
  ImmediateGUITests/
    InputStateTests.swift
    InteractionTests.swift
    LayoutTests.swift
    DrawListTests.swift
```

Initially, these files can remain in one executable target to avoid package restructuring overhead. Once the boundaries stabilize, `ImmediateGUI` can become a library target and the demo can become a separate executable target.

# Core Types

## 1. Pixel-Space Geometry

The current text renderer converts pixel positions into normalized device coordinates while constructing glyph instances. That conversion should move into the Metal backend. Everything above the backend should use logical pixels with a top-left origin.

```swift
struct Point: Equatable {
  var x: Float
  var y: Float
}

struct Size: Equatable {
  var width: Float
  var height: Float
}

struct Rect: Equatable {
  var origin: Point
  var size: Size

  func contains(_ point: Point) -> Bool
  func intersection(_ other: Rect) -> Rect?
}
```

Pixel-space coordinates make layout, hit-testing, clipping, and tests easier.

Logical points and drawable pixels must remain distinct. AppKit mouse coordinates and `MTKView.drawableSize` may differ on Retina displays. The UI should operate in view-space logical points, with the backend applying the backing scale when generating GPU coordinates.

## 2. Input Snapshot

Replace direct mutation of renderer properties in `NSEvent.addLocalMonitorForEvents` with an input accumulator.

```swift
struct InputState {
  var pointerPosition: Point = .zero
  var pointerDown = false
  var pointerPressed = false
  var pointerReleased = false

  var scrollDelta: Point = .zero
  var keysDown: Set<Key> = []
  var keysPressed: Set<Key> = []
  var textInput = ""
}
```

The distinction between held and edge-triggered state is essential:

- `pointerDown`: held across frames
- `pointerPressed`: false-to-true transition during this frame
- `pointerReleased`: true-to-false transition during this frame

AppKit callbacks should queue events. At frame start, those events become the frame's immutable input snapshot. At frame end, transient fields are cleared. This prevents clicks from being lost if an event arrives between draw callbacks.

## 3. Backend-Neutral Draw List

Start with commands rather than widgets:

```swift
enum DrawCommand {
  case fillRect(rect: Rect, color: Color)
  case strokeRect(rect: Rect, width: Float, color: Color)
  case text(position: Point, text: String, color: Color, scale: Float)
  case pushClip(Rect)
  case popClip
}

struct DrawList {
  private(set) var commands: [DrawCommand] = []

  mutating func fillRect(_ rect: Rect, color: Color)
  mutating func strokeRect(_ rect: Rect, width: Float, color: Color)
  mutating func text(_ text: String, at position: Point, color: Color)
  mutating func pushClip(_ rect: Rect)
  mutating func popClip()
}
```

An enum is easy to inspect and test. If profiling later shows that command dispatch or allocations are significant, it can be replaced with packed vertex and index buffers.

## 4. Widget Identity

Immediate-mode widgets need stable IDs across frames even though widget objects are not retained.

```swift
struct WidgetID: Hashable {
  let rawValue: UInt64
}
```

The context should maintain an ID stack:

```swift
ui.pushID("settings")
if ui.button("Save") { ... }
ui.popID()
```

A widget ID can be generated by hashing:

- the current ID stack
- the widget's explicit identifier or label
- optionally a call-site identifier during development

Do not identify a button only by its visible label. Two `"Delete"` buttons must be distinguishable. A convenient syntax is:

```swift
ui.button("Delete##account")
ui.button("Delete##document")
```

The text before `##` is displayed, while the complete string contributes to identity.

## 5. UI Interaction State

The UI context should own only state needed to interpret immediate calls:

```swift
struct UIContext {
  var input: InputState
  var drawList: DrawList

  private var hotID: WidgetID?
  private var activeID: WidgetID?
  private var focusedID: WidgetID?

  private var idStack: [WidgetID]
  private var layoutStack: [LayoutContext]
  private var clipStack: [Rect]
}
```

Definitions:

- **hot:** the pointer currently overlaps the widget
- **active:** the widget captured the press and is waiting for release
- **focused:** the widget receives keyboard or text input

Basic button behavior:

```swift
mutating func buttonBehavior(id: WidgetID, rect: Rect) -> ButtonResult {
  let hovered = currentClip.contains(input.pointerPosition)
    && rect.contains(input.pointerPosition)

  if hovered {
    hotID = id
  }

  if hovered && input.pointerPressed {
    activeID = id
  }

  let clicked =
    activeID == id &&
    hovered &&
    input.pointerReleased

  if activeID == id && input.pointerReleased {
    activeID = nil
  }

  return ButtonResult(
    hovered: hovered,
    held: activeID == id && input.pointerDown,
    clicked: clicked
  )
}
```

This behavior should be centralized so future widgets share consistent press and capture semantics.

# Refactor Phases

## Phase 1: Extract a Backend-Neutral Immediate Renderer

**Goal:** Reproduce the current screen through a `DrawList`, without widgets yet.

Create:

- `Geometry.swift`
- `Color.swift`
- `DrawCommand.swift`
- `DrawList.swift`
- `MetalRenderer.swift`

Move the current Metal initialization and command encoding out of the application entry point. Replace `drawText`'s hard-coded specimen generation with calls such as:

```swift
drawList.text(
  "5x7 PRINTABLE ASCII 20-7E",
  at: Point(x: 20, y: 20),
  color: .yellow
)
```

The backend should expand each text command into glyph instances.

### Completion Criteria

- The demo still displays the ASCII specimen.
- UI-facing code imports no Metal types.
- Coordinates outside the Metal backend are pixel-based.
- The Metal backend receives only viewport information and a draw list.
- `swift build` remains clean after each extraction.

## Phase 2: Generalize Metal Pipelines for GUI Primitives

**Goal:** Render solid and textured quads rather than maintaining a special triangle pipeline and a special text path.

Add support for:

- solid rectangles
- optional rectangle borders
- text glyph quads
- alpha blending
- scissor rectangles for clipping

A practical GPU representation is:

```swift
struct GUIVertex {
  var position: SIMD2<Float>
  var uv: SIMD2<Float>
  var color: SIMD4<Float>
}
```

Each rectangle becomes four vertices and six indices. Text glyphs use the same geometry format but sample the font atlas.

Possible pipeline approaches:

1. Keep separate solid-color and text pipelines initially.
2. Use one pipeline with a texture-mode flag and a 1x1 white texture for untextured geometry.

Separate pipelines are simpler initially. Draw commands should be batched while preserving order:

```text
solid batch
text batch
solid batch
clip change
text batch
```

Do not globally reorder translucent GUI commands by pipeline because their visual result depends on submission order.

### Buffer Management

The current implementation allocates a new Metal buffer every frame in `drawText`. Replace it with reusable, dynamically resized buffers:

- one vertex buffer
- one index buffer
- optionally one text-instance buffer
- two or three frame slots to avoid modifying GPU-visible memory that is still in use

Start with shared-storage buffers and grow capacity geometrically when necessary. Optimize further only after the command model works.

### Completion Criteria

- A test scene can draw overlapping colored rectangles and text.
- Resize behavior is correct.
- Alpha blending is correct.
- No per-glyph or per-widget Metal buffer allocation occurs.
- Clipping works through Metal scissor rectangles.

## Phase 3: Introduce Frame Lifecycle and AppKit Input

**Goal:** Establish the immediate-mode frame loop.

The frame lifecycle should be explicit:

```swift
func draw(in view: MTKView) {
  let input = eventQueue.consumeFrameInput()

  ui.beginFrame(
    input: input,
    viewport: view.bounds.size
  )

  buildUI(&ui, state: appState)

  let drawList = ui.endFrame()
  renderer.render(drawList, in: view)
}
```

Capture these AppKit events:

- `.mouseMoved`
- `.leftMouseDown`
- `.leftMouseUp`
- `.leftMouseDragged`
- `.scrollWheel`
- `.keyDown`
- `.keyUp`
- text input later

Prefer an `MTKView` subclass or a dedicated event adapter over a global local event monitor. This keeps input scoped to the correct view and provides cleaner coordinate conversion.

Initially, leave `MTKView` drawing continuously. Dirty or on-demand rendering can be added after correctness is established.

### Completion Criteria

- Pointer coordinates remain correct after resize and on Retina screens.
- A quick press and release cannot be lost between frames.
- Pointer capture works while dragging outside a widget.
- Keyboard events no longer mutate the renderer directly.

## Phase 4: Implement IDs and the First Button

**Goal:** Validate immediate-mode interaction end to end.

Implement:

- widget ID stack
- `hotID`
- `activeID`
- shared `buttonBehavior`
- `label`
- `button`
- a simple theme

Suggested theme:

```swift
struct Theme {
  var textColor: Color
  var panelColor: Color
  var buttonColor: Color
  var buttonHoveredColor: Color
  var buttonPressedColor: Color
  var borderColor: Color
  var padding: Float
  var itemSpacing: Float
}
```

Use a vertical slice as the acceptance test:

```swift
ui.label("Counter: \(state.count)")

if ui.button("Increment") {
  state.count += 1
}
```

This is the milestone where the project becomes a real immediate-mode GUI rather than only an immediate draw API.

### Completion Criteria

- Hover, press, release, and click states render distinctly.
- Pressing inside and releasing outside does not click.
- Pressing inside, dragging outside, and returning before release behaves consistently.
- Duplicate visible labels can be assigned distinct IDs.
- Application state stays outside `UIContext`.

## Phase 5: Add Layout

**Goal:** Stop requiring manually specified rectangles for every widget.

Start with a simple cursor-based vertical layout:

```swift
ui.beginPanel("demo", rect: panelRect)
ui.label("Controls")
ui.button("Increment")
ui.button("Reset")
ui.endPanel()
```

A `LayoutContext` could contain:

```swift
struct LayoutContext {
  var bounds: Rect
  var cursor: Point
  var availableWidth: Float
  var direction: Axis
  var spacing: Float
  var padding: Insets
}
```

Each widget should:

1. Measure its desired size.
2. Request the next rectangle.
3. Perform interaction against that rectangle.
4. Append draw commands.
5. Advance the cursor.

Add explicit helpers before attempting a sophisticated constraint system:

```swift
ui.sameLine()
ui.spacing(8)
ui.separator()
ui.setNextItemWidth(120)
```

Avoid building flexbox, retained layout nodes, or a generic constraint solver at this stage. A stack-based layout model fits immediate-mode APIs and is enough to establish the architecture.

## Phase 6: Add Panels and Clipping

**Goal:** Support nested UI regions.

Implement:

- panel backgrounds
- padding
- nested layout contexts
- clip stack
- scroll offset state
- scissor rectangle conversion in Metal

Persistent scroll offsets can live in keyed storage:

```swift
var widgetStorage: [WidgetID: WidgetStorage]
```

Do not use this storage for all application state. It should hold only widget-internal values such as scroll position, text-edit cursor, or open/closed state when the API explicitly owns it.

## Phase 7: Add Text Measurement and Richer Widgets

Once the basic loop is stable, add:

1. Text measurement using `FontAtlas`
2. Checkbox
3. Slider
4. Progress bar
5. Scrollable region
6. Keyboard focus and tab navigation
7. Text field and text input

Text fields should come later because they require substantially more infrastructure:

- focus
- Unicode text input
- selection
- cursor movement
- clipboard integration
- composition and input methods

The current ASCII bitmap font is suitable for bootstrapping labels and debugging, but not for production text input. Keep font measurement and glyph lookup behind an abstraction so a Core Text or FreeType-backed atlas can replace it later.

# Testing Strategy

The backend-neutral split enables most logic to be tested without opening a Metal window.

## Interaction Tests

Simulate consecutive frames:

```swift
// Frame 1: pointer outside
// Frame 2: press inside
// Frame 3: release inside
// Expect one click
```

Cover:

- press and release inside
- press inside and release outside
- press outside and release inside
- drag while active
- overlapping widgets
- clipped widgets
- duplicate labels with distinct IDs

## Layout Tests

Assert exact rectangles for:

- vertical stacks
- padding and spacing
- nested panels
- fixed versus available width
- empty containers
- clipping intersections

## Draw-List Tests

Build a known UI and verify:

- command order
- command geometry
- colors selected for idle, hovered, and active states
- balanced clip pushes and pops
- correct text positions

## Metal Smoke Tests

Keep these limited to integration concerns:

- shader and pipeline creation
- buffer growth
- empty draw list
- large draw list
- drawable resize
- clip conversion

# Recommended Commit Order

1. Add geometry, color, and draw-list types.
2. Rename `HelloTriangel.swift` and isolate application setup.
3. Move Metal code into `MetalRenderer`.
4. Render the current text specimen from draw commands.
5. Add solid-rectangle batching.
6. Add reusable dynamic GPU buffers.
7. Introduce an AppKit event adapter and frame input snapshots.
8. Add `UIContext`, widget IDs, and button behavior.
9. Build the counter/button demo.
10. Add vertical layout and a theme.
11. Add panels, clipping, and scrolling.
12. Split the package into GUI library, Metal backend, and demo targets.
13. Add non-Metal unit tests.

Each commit should keep the demo buildable. Avoid rewriting the entire renderer and UI system simultaneously.

# Recommended Decisions

- Use **top-left, pixel-space coordinates** throughout the GUI.
- Keep **application state external** to `UIContext`.
- Have the UI emit a **backend-neutral draw list**.
- Keep Metal entirely behind `MetalRenderer`.
- Use **stable hashed widget IDs** with an ID stack.
- Start with **vertical cursor layout**, not a constraint solver.
- Keep the existing 5x7 atlas for bootstrapping.
- Start with continuously rendered frames and optimize to dirty rendering later.
- Replace the current per-frame Metal buffer allocation before scaling to many widgets.
- Build one vertical slice—**panel + label + button + counter**—before adding more widget types.

# First Milestone

Replace the hard-coded font specimen with a panel containing a label and a clickable counter button, with all output generated through:

```text
UIContext -> DrawList -> MetalRenderer
```

At that point, the project will have the core of a real immediate-mode GUI rendering system, and later widgets can build on stable input, interaction, layout, and rendering abstractions.
