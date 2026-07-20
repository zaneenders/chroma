/// The ambient per-frame interaction context: the input snapshot, the focus
/// tree, and the retained navigation state immediate-mode widgets need,
/// owned and pumped by the rendering backend.
///
/// # UI is a tree, so input is tree movement
///
/// The framework's whole input language is the seven ``UICommand``s —
/// `up`, `down`, `left`, `right`, `in`, `out`, and `activate` — moving a
/// single cursor over the focus tree. Stacks are groups (their orientation
/// decides which commands move between their children); ``Interactive``
/// widgets are leaves. Groups containing no leaves are pruned, so the tree
/// is exactly the navigable UI.
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

  /// Set by an `activate` command and consumed by the selected leaf during
  /// this frame's draw.
  private var activatePending = false

  /// The previous frame's pointer position, so a parked pointer generates
  /// no hover macros.
  private var lastPointerPosition = Point(x: -1, y: -1)

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

    defer {
      selectedLeafID = selection.flatMap { tree?.node(at: $0)?.leafID }
      lastPointerPosition = input.pointerPosition
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

    // Scroll wheels speak the language too: one step per frame.
    if input.scrollDelta.y > 0 {
      apply(.up)
    } else if input.scrollDelta.y < 0 {
      apply(.down)
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
    tree = newTree
    builderRoot = nil
    builderStack = []
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

  /// Registers an interactive widget as a leaf of the enclosing group and
  /// reports its state for this frame: `hovered` means the cursor is on this
  /// widget, `held` means a pointer press is held on it, and `clicked` means
  /// it was activated this frame — by a click or by an `activate` command.
  public func interactiveBehavior(id: WidgetID, rect: Rect) -> ButtonState {
    guard let parent = builderStack.last else {
      preconditionFailure("interactiveBehavior outside of a frame; call beginFrame first")
    }
    parent.children.append(FocusNode(kind: .leaf(id), rect: rect))

    let selected = selectedLeafID == id
    let held = pressedLeaf == id && input.pointerDown
    var clicked = false
    if selected && activatePending {
      clicked = true
      activatePending = false
    }
    return ButtonState(hovered: selected, held: held, clicked: clicked)
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

  /// Applies one command to the cursor against the current tree. Movement
  /// is strict: sibling moves only apply when the parent group's axis
  /// matches the command's direction, and clamp at both ends. (Skips that
  /// bubble upward are a layer to build on top of this core.)
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
    case .up, .down, .left, .right:
      guard !selection.isEmpty,
        let parent = tree.node(at: Array(selection.dropLast())),
        let axis = parent.axis,
        let index = selection.last
      else { return }
      let delta: Int
      switch (axis, command) {
      case (.vertical, .up), (.horizontal, .left), (.none, .up), (.none, .left):
        delta = -1
      case (.vertical, .down), (.horizontal, .right), (.none, .down), (.none, .right):
        delta = 1
      default:
        return  // The command's direction doesn't apply to this group's axis.
      }
      let clamped = min(max(index + delta, 0), parent.children.count - 1)
      self.selection = Array(selection.dropLast()) + [clamped]
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
