import Observation

public enum InteractionMode: Equatable, Sendable {
  case movement
  case editing
}

@Observable
@MainActor
package final class Interaction {
  let caretClock = CaretClock()
  @ObservationIgnored var inputLengthText: String?
  @ObservationIgnored var inputLength = 0
  @ObservationIgnored var animationFrame = AnimationFrame(timestamp: 0)
  @ObservationIgnored var animationRequested = false

  package let textSelection = TextSelectionManager()

  package var fontMetrics = FontMetrics()

  @ObservationIgnored package private(set) var input = InputState()

  @ObservationIgnored package var frameRate: Double = 0

  package internal(set) var selection: [Int]?

  @ObservationIgnored var tree: FocusNode?

  var pressedLeaf: WidgetID?

  package internal(set) var editingLeaf: WidgetID?
  package private(set) var editingSessionGeneration: Int = 0

  package internal(set) var caretOffset: Int = 0
  package internal(set) var textSelectionRange: Range<Int>?
  @ObservationIgnored var textDragAnchor: Int?
  package internal(set) var editingText: String?

  public package(set) var mode: InteractionMode = .movement
  package var isTextEditing: Bool { mode == .editing }

  @ObservationIgnored var activatePending = false
  @ObservationIgnored private var redrawRequested = false
  @ObservationIgnored package var onRedrawRequested: (() -> Void)?
  @ObservationIgnored var pendingCommands: [Command] = []
  @ObservationIgnored var handledCommandIndices: Set<Int> = []
  struct ScopedCommandHandler {
    var path: [Int]
    var command: Command
    var action: @MainActor () -> CommandResult
  }
  @ObservationIgnored var commandHandlers: [ScopedCommandHandler] = []
  @ObservationIgnored var buildingCommandHandlers: [ScopedCommandHandler] = []
  @ObservationIgnored var actionRoles: [ActionRole: @MainActor () -> Void] = [:]

  @ObservationIgnored var lastPointerPosition = Point(x: -1, y: -1)

  package private(set) var dragOrigin: Point? = nil
  package private(set) var dragCurrent: Point = Point(x: -1, y: -1)
  package var isDragging: Bool { dragOrigin != nil && input.pointerDown }
  var isProcessingDrag: Bool { isDragging || (dragOrigin != nil && input.pointerReleased) }
  package var dragRect: Rect? {
    guard let origin = dragOrigin, isDragging else { return nil }
    return Rect(
      x: min(origin.x, dragCurrent.x),
      y: min(origin.y, dragCurrent.y),
      width: abs(dragCurrent.x - origin.x),
      height: abs(dragCurrent.y - origin.y))
  }

  @ObservationIgnored package var onCopy: (() -> String?)?
  @ObservationIgnored package var onSelectAll: (() -> Bool)?

  package func editableSelectionText() -> String? {
    guard isTextEditing, let range = textSelectionRange, let editingText else { return nil }
    let characters = Array(editingText)
    guard range.lowerBound >= 0, range.upperBound <= characters.count else { return nil }
    return String(characters[range])
  }

  package func copyText() -> String? {
    if let text = editableSelectionText() { return text }
    if let text = onCopy?(), !text.isEmpty { return text }
    return textSelection.selectedText()
  }

  package func selectAll(at point: Point) {
    if onSelectAll?() == true { return }
    textSelection.selectAll(at: point)
  }

  var scrollOffsets: [WidgetID: Float] = [:]
  var horizontalScrollOffsets: [WidgetID: Float] = [:]
  @ObservationIgnored var scrollLimits: [WidgetID: Float] = [:]
  @ObservationIgnored var horizontalScrollLimits: [WidgetID: Float] = [:]

  @ObservationIgnored var clipStack: [Rect] = []

  var selectedLeafID: WidgetID?

  @ObservationIgnored var builderRoot: FocusNode?
  @ObservationIgnored var builderStack: [FocusNode] = []
  @ObservationIgnored var builderPath: [Int] = []

  @ObservationIgnored var inputHandlers: [WidgetID: @MainActor () -> Void] = [:]
  @ObservationIgnored var buildingInputHandlers: [WidgetID: @MainActor () -> Void] = [:]
  @ObservationIgnored var buttonActions: [WidgetID: @MainActor () -> Void] = [:]
  @ObservationIgnored var buildingButtonActions: [WidgetID: @MainActor () -> Void] = [:]
  @ObservationIgnored var activatedLeaf: WidgetID?

  @ObservationIgnored var focusTargets: [ObjectIdentifier: (target: FocusTarget, id: WidgetID)] = [:]
  @ObservationIgnored var buildingFocusTargets: [ObjectIdentifier: (target: FocusTarget, id: WidgetID)] = [:]

  package init() {}

  func resetRegistrations() {
    for binding in focusTargets.values {
      binding.target.interaction = nil
      binding.target.pendingEditing = nil
    }
    focusTargets = [:]
    buildingFocusTargets = [:]
    textSelection.clear()
    textSelection.layoutRegistry.clear()
    scrollOffsets = [:]
    horizontalScrollOffsets = [:]
    scrollLimits = [:]
    horizontalScrollLimits = [:]
    animationRequested = false
    tree = nil
    pressedLeaf = nil
    inputHandlers = [:]
    buildingInputHandlers = [:]
    buttonActions = [:]
    buildingButtonActions = [:]
    commandHandlers = []
    buildingCommandHandlers = []
    actionRoles = [:]
    caretClock.setActive(false)
  }

  func beginEditing(_ id: WidgetID, caretOffset: Int) {
    editingSessionGeneration &+= 1
    editingLeaf = id
    self.caretOffset = caretOffset
    textSelectionRange = nil
    mode = .editing
  }

  func endEditing() {
    if editingLeaf != nil { editingSessionGeneration &+= 1 }
    editingLeaf = nil
    editingText = nil
    inputLengthText = nil
    inputLength = 0
    textSelectionRange = nil
    mode = .movement
  }

  func requestRedraw() {
    guard !redrawRequested else { return }
    redrawRequested = true
    onRedrawRequested?()
  }

  package func consumeRedrawRequest() -> Bool {
    defer { redrawRequested = false }
    return redrawRequested
  }

  @ObservationIgnored var refreshingRegistrations = false

  package func beginFrame(input: InputState) {
    buildingFocusTargets = [:]
    if refreshingRegistrations {
      // Registration draws must not replay the previous frame's input or activation.
      self.input = input
      textSelection.layoutRegistry.clear()
      activatedLeaf = nil
      activatePending = false
      actionRoles = [:]
      let root = FocusNode(kind: .group, rect: .zero)
      builderRoot = root
      builderStack = [root]
      builderPath = []
      clipStack = []
      buildingInputHandlers = [:]
      buildingButtonActions = [:]
      buildingCommandHandlers = []
      return
    }
    self.input = input
    activatePending = false
    pendingCommands = input.commands
    handledCommandIndices = []
    routePendingCommands()
    pendingCommands = []
    buildingCommandHandlers = []
    buildingInputHandlers = [:]
    buildingButtonActions = [:]
    activatedLeaf = nil

    let root = FocusNode(kind: .group, rect: .zero)
    builderRoot = root
    builderStack = [root]
    builderPath = []
    clipStack = []

    if input.pointerPressed {
      dragOrigin = input.pointerPressPosition
      dragCurrent = input.pointerPosition
      textDragAnchor = nil
      textSelection.clear()
    } else if input.pointerReleased {
      dragCurrent = input.pointerPosition
    } else if isDragging {
      dragCurrent = input.pointerPosition
    }
    textSelection.updateFromDrag(interaction: self)
    textSelection.layoutRegistry.clear()

    defer {
      selectedLeafID = selection.flatMap { tree?.node(at: $0)?.leafID }
      if let editingLeaf, editingLeaf != selectedLeafID {
        endEditing()
      }
      lastPointerPosition = input.pointerPosition
      for handler in inputHandlers.values { handler() }
      if activatePending, let id = selectedLeafID {
        activatePending = false
        activatedLeaf = id
        buttonActions[id]?()
      }
      actionRoles = [:]
    }

    guard let tree else { return }

    let hovered = tree.hitTest(input.pointerPosition)
    if input.pointerPressed {
      let pressed = tree.hitTest(input.pointerPressPosition)
      if let pressed { moveCursor(to: pressed) }
      pressedLeaf = pressed.flatMap { tree.node(at: $0)?.leafID }
    } else if dragOrigin == nil, input.pointerPosition != lastPointerPosition, let hovered,
      hovered != selection
    {
      moveCursor(to: hovered)
    }
    if input.pointerReleased {
      if let pressedLeaf, let hovered, hovered == selection,
        tree.node(at: hovered)?.leafID == pressedLeaf
      {
        apply(.action(.activate))
      }
      self.pressedLeaf = nil
    }
  }

  package func endFrame() {
    defer {
      if input.pointerReleased {
        dragOrigin = nil
        textDragAnchor = nil
      }
    }
    if !refreshingRegistrations { routePendingCommands() }
    guard let newTree = builderRoot else { return }
    if let selection, let oldTree = tree {
      if let id = oldTree.node(at: selection)?.leafID {
        self.selection = newTree.findLeaf(id) ?? newTree.clamped(selection)
      } else {
        self.selection = newTree.clamped(selection)
      }
    }
    if selection.flatMap({ newTree.node(at: $0)?.leafID }) == nil {
      selection = newTree.firstLeafPath()
    }
    if let editingLeaf, newTree.findLeaf(editingLeaf) == nil {
      endEditing()
    }
    if let pressedLeaf, newTree.findLeaf(pressedLeaf) == nil {
      self.pressedLeaf = nil
    }
    selectedLeafID = selection.flatMap { newTree.node(at: $0)?.leafID }
    scrollOffsets = scrollOffsets.filter { buildingInputHandlers[$0.key] != nil }
    horizontalScrollOffsets = horizontalScrollOffsets.filter { buildingInputHandlers[$0.key] != nil }
    scrollLimits = scrollLimits.filter { buildingInputHandlers[$0.key] != nil }
    horizontalScrollLimits = horizontalScrollLimits.filter { buildingInputHandlers[$0.key] != nil }
    textSelection.reconcile()
    tree = newTree
    resolveFocusTargets()
    selectedLeafID = selection.flatMap { newTree.node(at: $0)?.leafID }
    if let editingLeaf, editingLeaf != selectedLeafID { endEditing() }
    caretClock.setActive(editingLeaf != nil && textSelectionRange == nil)
    commandHandlers = buildingCommandHandlers
    inputHandlers = buildingInputHandlers
    buttonActions = buildingButtonActions
    builderRoot = nil
    builderStack = []
    activatePending = false
  }
}

@MainActor
extension Interaction {
  func beginGroup(rect: Rect) {
    guard let parent = builderStack.last else {
      preconditionFailure("beginGroup outside of a frame; call beginFrame first")
    }
    let node = FocusNode(kind: .group, rect: rect)
    parent.children.append(node)
    builderPath.append(parent.children.count - 1)
    builderStack.append(node)
  }

  @discardableResult
  func endGroup() -> Bool {
    guard builderStack.count > 1, let node = builderStack.popLast() else {
      preconditionFailure("endGroup without a matching beginGroup")
    }
    builderPath.removeLast()
    if node.children.isEmpty {
      builderStack.last?.children.removeLast()
      return false
    }
    return true
  }

  func focus(_ id: WidgetID, editing: Bool = false) {
    guard let tree, let path = tree.findLeaf(id) else { return }
    moveCursor(to: path)
    if editing {
      beginEditing(id, caretOffset: .max)
    }
  }

  func moveCursor(to path: [Int]) {
    guard tree?.node(at: path)?.isLeaf == true else { return }
    selection = path
  }

  private func isPrefix(_ prefix: [Int], of path: [Int]) -> Bool {
    prefix.count <= path.count && Array(path.prefix(prefix.count)) == prefix
  }

  func routePendingCommands() {
    for (index, command) in pendingCommands.enumerated() where !handledCommandIndices.contains(index) {
      let handlers =
        commandHandlers
        .filter { $0.command == command && isPrefix($0.path, of: selection ?? []) }
        .sorted { $0.path.count > $1.path.count }
      if handlers.contains(where: { $0.action() == .handled }) {
        handledCommandIndices.insert(index)
        continue
      }
      switch command {
      case .action(.submit):
        actionRoles[.defaultAction]?()
      case .action(.cancel), .action(.dismiss):
        actionRoles[.cancel]?()
      default:
        apply(command)
      }
    }
  }

  func apply(_ command: Command) {
    guard tree != nil, selection != nil else { return }
    switch command {
    case .application, .editing:
      return
    case .action(.activate):
      activatePending = true
    case .action(.submit), .action(.cancel), .action(.dismiss):
      return
    }
  }
}

@MainActor
extension Interaction {
  func pushClip(_ rect: Rect) {
    let clip = clipStack.last.flatMap { $0.intersection(rect) } ?? (clipStack.isEmpty ? rect : .zero)
    clipStack.append(clip)
  }

  func popClip() {
    guard !clipStack.isEmpty else {
      preconditionFailure("popClip without a matching pushClip")
    }
    clipStack.removeLast()
  }

  func interactiveBehavior(
    id: WidgetID, rect: Rect, role: ActionRole = .normal,
    action: (@MainActor () -> Void)? = nil
  ) -> ButtonState {
    guard let parent = builderStack.last else {
      preconditionFailure("interactiveBehavior outside of a frame; call beginFrame first")
    }
    parent.children.append(FocusNode(kind: .leaf(id), rect: clippedRect(rect), role: role))
    if role != .normal, let action { actionRoles[role] = action }

    let selected = selectedLeafID == id
    let held = pressedLeaf == id && input.pointerDown
    if let action { buildingButtonActions[id] = action }
    return ButtonState(hovered: selected, held: held, clicked: activatedLeaf == id)
  }

  func clippedRect(_ rect: Rect) -> Rect {
    guard let clip = clipStack.last else { return rect }
    return rect.intersection(clip) ?? .zero
  }
}

@MainActor
extension Interaction {
  package var selectionDescription: String {
    guard let selection else { return "—" }
    let path = selection.isEmpty ? "·" : selection.map(String.init).joined(separator: ".")
    let kind = selectedLeafID != nil ? "leaf" : selection.isEmpty ? "root" : "group"
    return "\(path) (\(kind))"
  }
}
