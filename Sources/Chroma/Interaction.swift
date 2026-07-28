/// The ambient per-frame interaction context: the input snapshot, the focus
/// tree, and the retained navigation state immediate-mode widgets need,
/// owned and pumped by the rendering backend.
///
/// # UI is a tree, so input is tree movement
///
/// The framework's whole input language is the ``UICommand`` set — `up`,
/// `down`, `left`, `right`, `in`, `out`, `activate`, and the flattened
/// `nextLeaf` / `previousLeaf` leaf-cycling commands — moving a single
/// cursor over the focus tree. Stacks are groups (their orientation
/// decides which commands move between their children); ``Interactive``
/// widgets are leaves. Groups containing no leaves are pruned, so the tree
/// is exactly the navigable UI.
///
/// Directional movement is flattened: a keypress takes the strict sibling
/// move when one applies and otherwise bubbles up to the nearest ancestor
/// where it does. At the outer edge it stops, preserving the current cursor.
///
/// Every device compiles into the language:
///
/// - **Keyboard** maps keys onto commands directly and enqueues them in
///   ``InputState/commands``; the backend's keymap is the only
///   device-specific piece.
/// - **The pointer is a macro generator.** Hovering a leaf compiles into the
///   move sequence that would walk the cursor from where it is to the
///   pointer's target — `out` to the common ancestor, then `in` and sibling
///   moves back down — and runs it through the same path as keystrokes. A
///   click is a macro plus `activate`. There is no separate hot widget: the
///   cursor is the only selection, and the last device to speak wins. A
///   parked pointer generates no macros, so keyboard movement is never
///   fought by the mouse.
///
/// **Text fields are insert mode.** Activating a ``TextField`` (click or
/// `activate` command) makes it the ``editingLeaf``: the backend stops
/// translating keys into commands and sends ``TextEditEvent``s instead, and
/// the field drains them during draw. The session ends on `.endEditing`
/// (escape/return) or whenever the cursor leaves the field — by any device,
/// since there is only one cursor. It is vim's normal/insert split, with
/// tree movement as normal mode.
///
/// # Frame lifecycle
///
/// Blocks are re-evaluated value types with no storage of their own, so
/// navigation state lives here, ImGui-style. The backend installs its
/// context as ``current`` and brackets every frame with
/// ``beginFrame(input:)`` / ``endFrame()``; stacks and interactive widgets
/// register themselves during draw via ``beginGroup(_:rect:)`` /
/// ``endGroup()`` and ``interactiveBehavior(id:rect:)``.
///
/// Commands run one frame behind: ``beginFrame(input:)`` applies them
/// against the *previous* frame's tree, and ``endFrame()`` finalizes the
/// freshly built tree and re-resolves the cursor — leaves follow their
/// ``WidgetID`` across re-layouts, groups clamp their path into whatever
/// shape remains.
@MainActor
public final class Interaction {
  /// The context blocks interact with. Backends replace this with their own
  /// instance at startup; until multi-window support arrives there is
  /// exactly one context per process.
  public static var current = Interaction()

  /// The current frame's input snapshot.
  public private(set) var input = InputState()

  /// Smoothed frames per second, maintained by the backend.
  public var frameRate: Double = 0

  /// The cursor: the path of the selected node in the most recent tree.
  /// `[]` selects the root group; nil only before the first tree exists.
  public private(set) var selection: [Int]?

  /// The most recent pointer-generated macro (hover or click), for display.
  /// Watching this string while moving the mouse is the fastest way to see
  /// that the mouse *is* the keyboard.
  public private(set) var lastMacro: [UICommand] = []

  /// The border color stroked around a group while the cursor is on it.
  public var groupCursorColor = Color(r: 0.35, g: 0.6, b: 1, a: 0.4)

  /// The previous frame's focus tree. All command application and
  /// hit-testing runs against this tree, one frame behind the draw.
  private var tree: FocusNode?

  /// The widget the pointer pressed on, while the press is held. Release on
  /// the same widget activates it; release anywhere else does not.
  private var pressedLeaf: WidgetID?

  /// The text field holding the keyboard, while an editing session is
  /// active. Set when a ``TextField`` is activated; cleared by an
  /// `.endEditing` event or by the cursor leaving the field (any device —
  /// there is only one cursor).
  public private(set) var editingLeaf: WidgetID?

  /// The caret's grapheme offset inside ``editingLeaf``'s text.
  public private(set) var caretOffset: Int = 0

  /// Whether a text field owns the keyboard. Backends check this to route
  /// key events to ``TextEditEvent``s instead of ``UICommand``s.
  public var isTextEditing: Bool { editingLeaf != nil }

  /// Set by an `activate` command and consumed by the selected leaf during
  /// this frame's draw.
  private var activatePending = false

  /// The previous frame's pointer position, so a parked pointer generates
  /// no hover macros.
  private var lastPointerPosition = Point(x: -1, y: -1)

  // MARK: Drag tracking (for text selection)

  /// The position where the most recent pointer press occurred, while the
  /// press is still held. Nil between drags.
  public private(set) var dragOrigin: Point? = nil
  /// The current pointer position during an active drag. Updated every frame.
  public private(set) var dragCurrent: Point = Point(x: -1, y: -1)
  /// `true` while a pointer drag is in progress (press held + moved).
  public var isDragging: Bool { dragOrigin != nil && input.pointerDown }
  /// The bounding rect of the active drag, from origin to current position.
  /// Nil when no drag is in progress.
  public var dragRect: Rect? {
    guard let origin = dragOrigin, isDragging else { return nil }
    return Rect(
      x: min(origin.x, dragCurrent.x),
      y: min(origin.y, dragCurrent.y),
      width: abs(dragCurrent.x - origin.x),
      height: abs(dragCurrent.y - origin.y))
  }

  // MARK: Clipboard

  /// Called by the backend when the user presses Cmd+C (or equivalent) while
  /// not in text-editing mode. Return the string to copy to the system
  /// clipboard, or nil to ignore.
  public var onCopy: (() -> String?)?

  /// Retained scroll positions and prior limits, keyed by a stable scroll-view ID.
  private var scrollOffsets: [WidgetID: Float] = [:]
  private var horizontalScrollOffsets: [WidgetID: Float] = [:]
  private var scrollLimits: [WidgetID: Float] = [:]
  private var horizontalScrollLimits: [WidgetID: Float] = [:]
  /// Viewports from the previous frame suppress the legacy wheel-to-focus
  /// mapping when the wheel belongs to a scroll container.
  private var scrollViewports: [Rect] = []
  private var buildingScrollViewports: [Rect] = []

  /// Clips inherited by blocks as they draw. The effective clip is stored on
  /// focus-tree leaves so pointer hit testing agrees with rendered clipping.
  private var clipStack: [Rect] = []

  /// The selected leaf's identity for this frame, resolved during
  /// ``beginFrame(input:)`` so leaves are matched by ``WidgetID`` across the
  /// frame boundary. Nil when the cursor is on a group.
  private var selectedLeafID: WidgetID?

  // MARK: Tree building (valid between beginFrame and endFrame)

  /// The root of the tree being built this frame.
  private var builderRoot: FocusNode?
  /// The stack of open groups; the last element receives new children.
  private var builderStack: [FocusNode] = []
  /// The path of the innermost open group in the building tree.
  private var builderPath: [Int] = []

  public init() {}

  // MARK: Frame lifecycle

  /// Installs the frame's input snapshot and applies everything it carries
  /// to the cursor, in device order: pointer macros first (hover moves the
  /// cursor to the hovered leaf, press also arms it, release on the same
  /// leaf activates), then scroll-wheel steps, then the keyboard's queued
  /// commands — so within one frame, the keyboard speaks last.
  ///
  /// Backends call this once per frame before drawing.
  public func beginFrame(input: InputState) {
    self.input = input
    activatePending = false

    // Start the new frame's tree. Registration during draw appends here.
    let root = FocusNode(kind: .group(.vertical), rect: .zero)
    builderRoot = root
    builderStack = [root]
    builderPath = []
    clipStack = []
    buildingScrollViewports = []

    // Update text selection state from the previous frame's drag, then
    // clear registries so this frame's draw can re-register layouts.
    if input.pointerPressed {
      TextSelectionManager.shared.clear()
    }
    TextSelectionManager.shared.updateFromDrag()
    PlainTextLayoutRegistry.clear()

    defer {
      selectedLeafID = selection.flatMap { tree?.node(at: $0)?.leafID }
      if let editingLeaf, editingLeaf != selectedLeafID {
        self.editingLeaf = nil  // The cursor left the field: insert mode ends.
      }
      lastPointerPosition = input.pointerPosition
      // Drag tracking
      if input.pointerPressed {
        dragOrigin = input.pointerPressPosition
      }
      if input.pointerReleased {
        dragOrigin = nil
      }
      if isDragging {
        dragCurrent = input.pointerPosition
      }
    }

    guard let tree else { return }  // First frame: no tree to navigate yet.

    // The pointer speaks first: hover and press are macros, click is a
    // macro plus activate.
    let hovered = tree.hitTest(input.pointerPosition)
    if input.pointerPressed {
      if let hovered { moveCursor(to: hovered) }
      pressedLeaf = hovered.flatMap { tree.node(at: $0)?.leafID }
    } else if input.pointerPosition != lastPointerPosition, let hovered, hovered != selection {
      moveCursor(to: hovered)
    }
    if input.pointerReleased {
      if let pressedLeaf, let hovered, hovered == selection,
        tree.node(at: hovered)?.leafID == pressedLeaf
      {
        apply(.activate)
      }
      self.pressedLeaf = nil
    }

    // Outside a scroll viewport, wheels retain the original focus-navigation
    // behavior. Inside one, the viewport consumes the raw delta during draw.
    let wheelIsOverScrollView = scrollViewports.contains { $0.contains(input.pointerPosition) }
    if !wheelIsOverScrollView {
      if input.scrollDelta.y > 0 {
        apply(.up)
      } else if input.scrollDelta.y < 0 {
        apply(.down)
      }
    }

    // The keyboard speaks last.
    for command in input.commands { apply(command) }
  }

  /// Finalizes the frame: the tree built during draw becomes the tree
  /// navigation runs against next frame, and the cursor is re-resolved
  /// against it — leaves follow their ``WidgetID`` wherever they moved,
  /// groups clamp their path into the new shape. When nothing is selected
  /// (startup, or the selected widget vanished entirely), the cursor starts
  /// on the first leaf.
  ///
  /// Backends call this once per frame after drawing.
  public func endFrame() {
    guard let newTree = builderRoot else { return }
    if let selection, let oldTree = tree {
      if let id = oldTree.node(at: selection)?.leafID {
        self.selection = newTree.findLeaf(id) ?? newTree.clamped(selection)
      } else {
        self.selection = newTree.clamped(selection)
      }
    }
    if selection == nil {
      selection = newTree.firstLeafPath()
    }
    if let editingLeaf, newTree.findLeaf(editingLeaf) == nil {
      self.editingLeaf = nil  // The field vanished from the UI mid-edit.
    }
    tree = newTree
    scrollViewports = buildingScrollViewports
    builderRoot = nil
    builderStack = []
    buildingScrollViewports = []
    activatePending = false
  }

  // MARK: Registration during draw

  /// Begins a focus group for a stack being drawn. Every stack registers,
  /// but groups that end up containing no interactive leaves are pruned at
  /// ``endGroup()``, so only navigable structure reaches the tree.
  public func beginGroup(_ axis: FocusAxis, rect: Rect) {
    guard let parent = builderStack.last else {
      preconditionFailure("beginGroup outside of a frame; call beginFrame first")
    }
    let node = FocusNode(kind: .group(axis), rect: rect)
    parent.children.append(node)
    builderPath.append(parent.children.count - 1)
    builderStack.append(node)
  }

  /// Closes the innermost group, pruning it if nothing interactive was
  /// registered inside. Pruning happens as groups close — before later
  /// siblings register — so paths observed during draw already match the
  /// final tree.
  public func endGroup() {
    guard builderStack.count > 1, let node = builderStack.popLast() else {
      preconditionFailure("endGroup without a matching beginGroup")
    }
    builderPath.removeLast()
    if node.children.isEmpty {
      builderStack.last?.children.removeLast()
    }
  }

  /// Whether the cursor is on the group currently being built. Stacks check
  /// this after drawing their children to stroke the group cursor.
  public var isCurrentGroupSelected: Bool {
    guard let selection, selectedLeafID == nil else { return false }
    return selection == builderPath
  }

  // MARK: Clipping and retained scroll state

  /// Narrows pointer hit testing to `rect` until the matching ``popClip()``.
  /// Draw containers call this alongside `DrawList.pushClip`.
  public func pushClip(_ rect: Rect) {
    let clip = clipStack.last.flatMap { $0.intersection(rect) } ?? (clipStack.isEmpty ? rect : .zero)
    clipStack.append(clip)
  }

  public func popClip() {
    guard !clipStack.isEmpty else {
      preconditionFailure("popClip without a matching pushClip")
    }
    clipStack.removeLast()
  }

  /// Registers a viewport for wheel routing on the next frame.
  public func registerScrollViewport(_ rect: Rect) {
    buildingScrollViewports.append(rect)
  }

  /// Returns the retained content offset for a scroll view.
  public func scrollOffset(for id: WidgetID) -> Float {
    scrollOffsets[id, default: 0]
  }

  /// Stores a clamped content offset for a scroll view.
  public func setScrollOffset(_ offset: Float, for id: WidgetID) {
    scrollOffsets[id] = max(0, offset)
  }

  /// Returns the retained horizontal content offset for a scroll view.
  public func horizontalScrollOffset(for id: WidgetID) -> Float {
    horizontalScrollOffsets[id, default: 0]
  }

  /// Stores a clamped horizontal content offset for a scroll view.
  public func setHorizontalScrollOffset(_ offset: Float, for id: WidgetID) {
    horizontalScrollOffsets[id] = max(0, offset)
  }

  /// The previous frame's maximum vertical offset, used to preserve
  /// stick-to-bottom while streaming content grows.
  public func scrollLimit(for id: WidgetID) -> Float {
    scrollLimits[id, default: 0]
  }

  public func setScrollLimit(_ limit: Float, for id: WidgetID) {
    scrollLimits[id] = max(0, limit)
  }

  /// Returns the maximum retained horizontal offset for a scroll view.
  public func horizontalScrollLimit(for id: WidgetID) -> Float {
    horizontalScrollLimits[id, default: 0]
  }

  public func setHorizontalScrollLimit(_ limit: Float, for id: WidgetID) {
    horizontalScrollLimits[id] = max(0, limit)
  }

  /// Registers an interactive widget as a leaf of the enclosing group and
  /// reports its state for this frame: `hovered` means the cursor is on this
  /// widget, `held` means a pointer press is held on it, and `clicked` means
  /// it was activated this frame — by a click or by an `activate` command.
  public func interactiveBehavior(id: WidgetID, rect: Rect) -> ButtonState {
    guard let parent = builderStack.last else {
      preconditionFailure("interactiveBehavior outside of a frame; call beginFrame first")
    }
    parent.children.append(FocusNode(kind: .leaf(id), rect: clippedRect(rect)))

    let selected = selectedLeafID == id
    let held = pressedLeaf == id && input.pointerDown
    var clicked = false
    if selected && activatePending {
      clicked = true
      activatePending = false
    }
    return ButtonState(hovered: selected, held: held, clicked: clicked)
  }

  /// Registers a text-input widget as a leaf of the enclosing group and runs
  /// its editing session for this frame.
  ///
  /// Activation — a click, or an `activate` command while selected — enters
  /// insert mode: the field becomes ``editingLeaf`` with the caret at the end
  /// of its text, and the backend starts sending ``TextEditEvent``s instead
  /// of navigation commands. While editing, this drains the frame's text
  /// events in order, mutating the text through `onChange`; `.endEditing`
  /// ends the session, as does the cursor leaving the field by any device.
  ///
  /// `text` is the widget's current value, re-read every frame; `onChange`
  /// fires at most once per frame with the result of applying all of the
  /// frame's edits. `onSubmit`, when provided, fires on ``TextEditEvent/submit``
  /// (return) with the field's current text and the session stays in insert
  /// mode; without it, submit ends the session like ``TextEditEvent/endEditing``.
  public func textInputBehavior(
    id: WidgetID,
    rect: Rect,
    text: String,
    onChange: (String) -> Void,
    onSubmit: ((String) -> Void)? = nil
  ) -> TextInputState {
    guard let parent = builderStack.last else {
      preconditionFailure("textInputBehavior outside of a frame; call beginFrame first")
    }
    parent.children.append(FocusNode(kind: .leaf(id), rect: clippedRect(rect)))

    let selected = selectedLeafID == id
    let held = pressedLeaf == id && input.pointerDown

    // Activation (click or `activate` command) enters insert mode.
    if selected && activatePending {
      activatePending = false
      editingLeaf = id
      caretOffset = text.count
    }

    var editing = editingLeaf == id
    if editing {
      var characters = Array(text)
      caretOffset = min(caretOffset, characters.count)
      var changed = false
      eventLoop: for event in input.textEvents {
        switch event {
        case .insert(let inserted):
          let graft = Array(inserted)
          characters.insert(contentsOf: graft, at: caretOffset)
          caretOffset += graft.count
          changed = true
        case .backspace:
          if caretOffset > 0 {
            characters.remove(at: caretOffset - 1)
            caretOffset -= 1
            changed = true
          }
        case .deleteForward:
          if caretOffset < characters.count {
            characters.remove(at: caretOffset)
            changed = true
          }
        case .moveCaretLeft:
          caretOffset = max(0, caretOffset - 1)
        case .moveCaretRight:
          caretOffset = min(characters.count, caretOffset + 1)
        case .moveCaretToStart:
          caretOffset = 0
        case .moveCaretToEnd:
          caretOffset = characters.count
        case .submit:
          if let onSubmit {
            if changed {
              onChange(String(characters))
              changed = false
            }
            onSubmit(String(characters))
          } else {
            editingLeaf = nil
            editing = false
            break eventLoop
          }
        case .endEditing:
          editingLeaf = nil
          editing = false
          break eventLoop  // The session is over; drop the rest of the frame.
        }
      }
      if changed {
        onChange(String(characters))
      }
    }
    return TextInputState(
      hovered: selected, held: held, editing: editing,
      caretOffset: editing ? caretOffset : nil)
  }

  private func clippedRect(_ rect: Rect) -> Rect {
    guard let clip = clipStack.last else { return rect }
    return rect.intersection(clip) ?? .zero
  }

  // MARK: Display helpers

  /// A compact description of the cursor for status displays:
  /// `"0.0.2 (leaf)"`, `"0.1 (group)"`, or `"· (root)"`.
  public var selectionDescription: String {
    guard let selection else { return "—" }
    let path = selection.isEmpty ? "·" : selection.map(String.init).joined(separator: ".")
    let kind = selectedLeafID != nil ? "leaf" : selection.isEmpty ? "root" : "group"
    return "\(path) (\(kind))"
  }

  /// The last pointer macro as a command string, e.g. `"out in down down"`.
  public var lastMacroDescription: String {
    lastMacro.isEmpty ? "—" : lastMacro.map(\.label).joined(separator: " ")
  }

  // MARK: Command application

  /// Moves the cursor to the leaf with `id`, if it exists in the most recent
  /// tree, and optionally starts an editing session on it with the caret at
  /// the end of its text (clamped on the field's next draw).
  ///
  /// Use sparingly — one cursor means programmatic focus steals from the
  /// user. Intended for one-shot requests like focusing a chat composer
  /// after launch or after a modal closes.
  public func focus(_ id: WidgetID, editing: Bool = false) {
    guard let tree, let path = tree.findLeaf(id) else { return }
    moveCursor(to: path)
    if editing {
      editingLeaf = id
      caretOffset = .max
    }
  }

  /// Walks the cursor to `path` by generating the macro between here and
  /// there and running it through the normal command path, recording it as
  /// the last pointer macro.
  private func moveCursor(to path: [Int]) {
    guard let tree else { return }
    if selection == nil { selection = [] }
    let commands = tree.macro(from: selection ?? [], to: path)
    for command in commands { apply(command) }
    if !commands.isEmpty { lastMacro = commands }
  }

  /// Applies one command to the cursor against the current tree.
  private func apply(_ command: UICommand) {
    guard let tree, let selection else { return }
    switch command {
    case .activate:
      activatePending = true
    case .in:
      if let node = tree.node(at: selection), !node.children.isEmpty {
        self.selection = selection + [0]
      }
    case .out:
      if !selection.isEmpty {
        self.selection = Array(selection.dropLast())
      }
    case .pageUp, .pageDown, .home, .end:
      return  // Viewport containers consume these during their draw.
    case .nextLeaf, .previousLeaf:
      cycleLeaf(forward: command == .nextLeaf)
    case .up, .down, .left, .right:
      flattenedMove(command)
    }
  }

  /// The step a directional command takes inside a group of `axis`, or nil
  /// when the direction doesn't apply to that axis. Axis-less (overlapping)
  /// groups accept every direction.
  private func directionDelta(_ command: UICommand, axis: FocusAxis) -> Int? {
    switch (axis, command) {
    case (.vertical, .up), (.horizontal, .left), (.none, .up), (.none, .left):
      return -1
    case (.vertical, .down), (.horizontal, .right), (.none, .down), (.none, .right):
      return 1
    default:
      return nil
    }
  }

  /// Flattened directional movement: a strict sibling move when one applies
  /// at the cursor's own level; otherwise the command bubbles up to the
  /// nearest ancestor where it applies, landing on the edge leaf of the
  /// subtree entered. When no ancestor allows the move, the cursor stays put.
  private func flattenedMove(_ command: UICommand) {
    guard let tree, let selection else { return }
    let forward = command == .down || command == .right

    // Walk from the cursor's own group upward looking for a level where the
    // move applies. A move at the cursor's own level is the classic sibling
    // move and lands on the node itself (group or leaf); a bubbled move
    // enters a new subtree, so it lands on that subtree's edge leaf.
    var level = selection.count - 1
    while level >= 0 {
      let parentPath = Array(selection.prefix(level))
      guard let parent = tree.node(at: parentPath), let axis = parent.axis else { break }
      if let delta = directionDelta(command, axis: axis) {
        let next = selection[level] + delta
        if next >= 0, next < parent.children.count {
          var newPath = parentPath + [next]
          if level < selection.count - 1 {
            // Bubbled: descend to the edge leaf of the entered subtree.
            while let node = tree.node(at: newPath), !node.isLeaf, !node.children.isEmpty {
              newPath.append(forward ? 0 : node.children.count - 1)
            }
          }
          self.selection = newPath
          return
        }
      }
      level -= 1
    }

    // Nothing applied at any level: this is the outer edge, so stay put.
  }

  /// Moves the cursor through the leaves in depth-first (document) order,
  /// wrapping at the ends. DFS paths compare lexicographically in document
  /// order, so a cursor on a group resolves naturally: `nextLeaf` selects
  /// the first leaf after it, `previousLeaf` the last leaf before it.
  private func cycleLeaf(forward: Bool) {
    guard let tree, let selection else { return }
    let leaves = tree.leafPaths()
    guard let first = leaves.first, let last = leaves.last else { return }
    if forward {
      self.selection = leaves.first(where: { selection.lexicographicallyPrecedes($0) }) ?? first
    } else {
      self.selection = leaves.last(where: { $0.lexicographicallyPrecedes(selection) }) ?? last
    }
  }
}

/// How a widget currently interacts with the cursor.
public enum InteractionPhase: Equatable, Sendable {
  case idle
  /// The cursor is on the widget (reached by pointer macro or keystrokes).
  case hovered
  /// A pointer press is held on the widget.
  case pressed
}

/// The result of evaluating the cursor for one widget this frame.
public struct ButtonState: Equatable, Sendable {
  /// The cursor is on the widget.
  public var hovered: Bool
  /// A pointer press captured the widget and is still down.
  public var held: Bool
  /// The widget was activated this frame: a completed click, or an
  /// `activate` command while selected.
  public var clicked: Bool

  public init(hovered: Bool, held: Bool, clicked: Bool) {
    self.hovered = hovered
    self.held = held
    self.clicked = clicked
  }

  /// The phase used for styling this frame.
  public var phase: InteractionPhase {
    held ? .pressed : hovered ? .hovered : .idle
  }
}

/// The result of evaluating a text-input widget for one frame.
public struct TextInputState: Equatable, Sendable {
  /// The cursor is on the field.
  public var hovered: Bool
  /// A pointer press captured the field and is still down.
  public var held: Bool
  /// The field owns the keyboard this frame (insert mode).
  public var editing: Bool
  /// The caret's grapheme offset, or nil when not editing.
  public var caretOffset: Int?

  public init(hovered: Bool, held: Bool, editing: Bool, caretOffset: Int?) {
    self.hovered = hovered
    self.held = held
    self.editing = editing
    self.caretOffset = caretOffset
  }

  /// The phase used for styling this frame.
  public var phase: InteractionPhase {
    held ? .pressed : hovered ? .hovered : .idle
  }
}
