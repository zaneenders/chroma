@MainActor
public final class Interaction {
  public static var current = Interaction()

  public let textSelection = TextSelectionManager()

  public var fontMetrics = FontMetrics()

  public private(set) var input = InputState()

  public var frameRate: Double = 0

  public private(set) var selection: [Int]?

  public private(set) var lastMacro: [UICommand] = []

  public var groupCursorColor = Color(r: 0.35, g: 0.6, b: 1, a: 0.4)

  private var tree: FocusNode?

  private var pressedLeaf: WidgetID?

  public private(set) var editingLeaf: WidgetID?

  public private(set) var caretOffset: Int = 0

  public var isTextEditing: Bool { editingLeaf != nil }

  private var activatePending = false

  private var lastPointerPosition = Point(x: -1, y: -1)

  public private(set) var dragOrigin: Point? = nil
  public private(set) var dragCurrent: Point = Point(x: -1, y: -1)
  public var isDragging: Bool { dragOrigin != nil && input.pointerDown }
  public var dragRect: Rect? {
    guard let origin = dragOrigin, isDragging else { return nil }
    return Rect(
      x: min(origin.x, dragCurrent.x),
      y: min(origin.y, dragCurrent.y),
      width: abs(dragCurrent.x - origin.x),
      height: abs(dragCurrent.y - origin.y))
  }

  public var onCopy: (() -> String?)?

  private var scrollOffsets: [WidgetID: Float] = [:]
  private var horizontalScrollOffsets: [WidgetID: Float] = [:]
  private var scrollLimits: [WidgetID: Float] = [:]
  private var horizontalScrollLimits: [WidgetID: Float] = [:]
  private var scrollViewports: [Rect] = []
  private var buildingScrollViewports: [Rect] = []

  private var clipStack: [Rect] = []

  private var selectedLeafID: WidgetID?

  private var builderRoot: FocusNode?
  private var builderStack: [FocusNode] = []
  private var builderPath: [Int] = []

  public init() {}

  public func beginFrame(input: InputState) {
    self.input = input
    activatePending = false

    let root = FocusNode(kind: .group(.vertical), rect: .zero)
    builderRoot = root
    builderStack = [root]
    builderPath = []
    clipStack = []
    buildingScrollViewports = []

    if input.pointerPressed {
      textSelection.clear()
    }
    textSelection.updateFromDrag(interaction: self)
    textSelection.layoutRegistry.clear()

    defer {
      selectedLeafID = selection.flatMap { tree?.node(at: $0)?.leafID }
      if let editingLeaf, editingLeaf != selectedLeafID {
        self.editingLeaf = nil
      }
      lastPointerPosition = input.pointerPosition
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

    guard let tree else { return }

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

    let wheelIsOverScrollView = scrollViewports.contains { $0.contains(input.pointerPosition) }
    if !wheelIsOverScrollView {
      if input.scrollDelta.y > 0 {
        apply(.up)
      } else if input.scrollDelta.y < 0 {
        apply(.down)
      }
    }

    for command in input.commands { apply(command) }
  }

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
      self.editingLeaf = nil
    }
    tree = newTree
    scrollViewports = buildingScrollViewports
    builderRoot = nil
    builderStack = []
    buildingScrollViewports = []
    activatePending = false
  }


  public func beginGroup(_ axis: FocusAxis, rect: Rect) {
    guard let parent = builderStack.last else {
      preconditionFailure("beginGroup outside of a frame; call beginFrame first")
    }
    let node = FocusNode(kind: .group(axis), rect: rect)
    parent.children.append(node)
    builderPath.append(parent.children.count - 1)
    builderStack.append(node)
  }

  public func endGroup() {
    guard builderStack.count > 1, let node = builderStack.popLast() else {
      preconditionFailure("endGroup without a matching beginGroup")
    }
    builderPath.removeLast()
    if node.children.isEmpty {
      builderStack.last?.children.removeLast()
    }
  }

  public var isCurrentGroupSelected: Bool {
    guard let selection, selectedLeafID == nil else { return false }
    return selection == builderPath
  }


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

  public func registerScrollViewport(_ rect: Rect) {
    buildingScrollViewports.append(rect)
  }

  public func scrollOffset(for id: WidgetID) -> Float {
    scrollOffsets[id, default: 0]
  }

  public func setScrollOffset(_ offset: Float, for id: WidgetID) {
    scrollOffsets[id] = max(0, offset)
  }

  public func horizontalScrollOffset(for id: WidgetID) -> Float {
    horizontalScrollOffsets[id, default: 0]
  }

  public func setHorizontalScrollOffset(_ offset: Float, for id: WidgetID) {
    horizontalScrollOffsets[id] = max(0, offset)
  }

  public func scrollLimit(for id: WidgetID) -> Float {
    scrollLimits[id, default: 0]
  }

  public func setScrollLimit(_ limit: Float, for id: WidgetID) {
    scrollLimits[id] = max(0, limit)
  }

  public func horizontalScrollLimit(for id: WidgetID) -> Float {
    horizontalScrollLimits[id, default: 0]
  }

  public func setHorizontalScrollLimit(_ limit: Float, for id: WidgetID) {
    horizontalScrollLimits[id] = max(0, limit)
  }

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
          break eventLoop
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


  public var selectionDescription: String {
    guard let selection else { return "—" }
    let path = selection.isEmpty ? "·" : selection.map(String.init).joined(separator: ".")
    let kind = selectedLeafID != nil ? "leaf" : selection.isEmpty ? "root" : "group"
    return "\(path) (\(kind))"
  }

  public var lastMacroDescription: String {
    lastMacro.isEmpty ? "—" : lastMacro.map(\.label).joined(separator: " ")
  }


  public func focus(_ id: WidgetID, editing: Bool = false) {
    guard let tree, let path = tree.findLeaf(id) else { return }
    moveCursor(to: path)
    if editing {
      editingLeaf = id
      caretOffset = .max
    }
  }

  private func moveCursor(to path: [Int]) {
    guard let tree else { return }
    if selection == nil { selection = [] }
    let commands = tree.macro(from: selection ?? [], to: path)
    for command in commands { apply(command) }
    if !commands.isEmpty { lastMacro = commands }
  }

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
      return
    case .nextLeaf, .previousLeaf:
      cycleLeaf(forward: command == .nextLeaf)
    case .up, .down, .left, .right:
      flattenedMove(command)
    }
  }

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

  private func flattenedMove(_ command: UICommand) {
    guard let tree, let selection else { return }
    let forward = command == .down || command == .right

    var level = selection.count - 1
    while level >= 0 {
      let parentPath = Array(selection.prefix(level))
      guard let parent = tree.node(at: parentPath), let axis = parent.axis else { break }
      if let delta = directionDelta(command, axis: axis) {
        let next = selection[level] + delta
        if next >= 0, next < parent.children.count {
          var newPath = parentPath + [next]
          if level < selection.count - 1 {
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

  }

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

public enum InteractionPhase: Equatable, Sendable {
  case idle
  case hovered
  case pressed
}

public struct ButtonState: Equatable, Sendable {
  public var hovered: Bool
  public var held: Bool
  public var clicked: Bool

  public init(hovered: Bool, held: Bool, clicked: Bool) {
    self.hovered = hovered
    self.held = held
    self.clicked = clicked
  }

  public var phase: InteractionPhase {
    held ? .pressed : hovered ? .hovered : .idle
  }
}

public struct TextInputState: Equatable, Sendable {
  public var hovered: Bool
  public var held: Bool
  public var editing: Bool
  public var caretOffset: Int?

  public init(hovered: Bool, held: Bool, editing: Bool, caretOffset: Int?) {
    self.hovered = hovered
    self.held = held
    self.editing = editing
    self.caretOffset = caretOffset
  }

  public var phase: InteractionPhase {
    held ? .pressed : hovered ? .hovered : .idle
  }
}
