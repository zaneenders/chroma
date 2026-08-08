@MainActor
package final class Interaction {
  package static var current = Interaction()

  package let textSelection = TextSelectionManager()

  package var fontMetrics = FontMetrics()

  package private(set) var input = InputState()

  package var frameRate: Double = 0

  package internal(set) var selection: [Int]?

  package internal(set) var lastMacro: [UICommand] = []

  package var groupCursorColor = Color(r: 0.35, g: 0.6, b: 1, a: 0.4)

  var tree: FocusNode?

  var pressedLeaf: WidgetID?

  package internal(set) var editingLeaf: WidgetID?

  package internal(set) var caretOffset: Int = 0

  package var isTextEditing: Bool { editingLeaf != nil }

  var activatePending = false
  private var redrawRequested = false
  var pendingCommands: [Command] = []
  var handledCommandIndices: Set<Int> = []
  struct ScopedCommandHandler {
    var path: [Int]
    var command: Command
    var action: @MainActor () -> CommandResult
  }
  var commandHandlers: [ScopedCommandHandler] = []
  var buildingCommandHandlers: [ScopedCommandHandler] = []
  var actionRoles: [ActionRole: @MainActor () -> Void] = [:]

  var lastPointerPosition = Point(x: -1, y: -1)

  package private(set) var dragOrigin: Point? = nil
  package private(set) var dragCurrent: Point = Point(x: -1, y: -1)
  package var isDragging: Bool { dragOrigin != nil && input.pointerDown }
  package var dragRect: Rect? {
    guard let origin = dragOrigin, isDragging else { return nil }
    return Rect(
      x: min(origin.x, dragCurrent.x),
      y: min(origin.y, dragCurrent.y),
      width: abs(dragCurrent.x - origin.x),
      height: abs(dragCurrent.y - origin.y))
  }

  package var onCopy: (() -> String?)?

  var scrollOffsets: [WidgetID: Float] = [:]
  var horizontalScrollOffsets: [WidgetID: Float] = [:]
  var scrollLimits: [WidgetID: Float] = [:]
  var horizontalScrollLimits: [WidgetID: Float] = [:]
  var scrollViewports: [Rect] = []
  var buildingScrollViewports: [Rect] = []

  var clipStack: [Rect] = []

  var selectedLeafID: WidgetID?

  var builderRoot: FocusNode?
  var builderStack: [FocusNode] = []
  var builderPath: [Int] = []

  package init() {}

  func requestRedraw() {
    redrawRequested = true
  }

  package func consumeRedrawRequest() -> Bool {
    defer { redrawRequested = false }
    return redrawRequested
  }

  package func beginFrame(input: InputState) {
    self.input = input
    activatePending = false
    pendingCommands = input.semanticCommands
    handledCommandIndices = []
    routePendingCommands()
    pendingCommands = []
    buildingCommandHandlers = []
    actionRoles = [:]

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

  }

  package func endFrame() {
    routePendingCommands()
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
    commandHandlers = buildingCommandHandlers
    scrollViewports = buildingScrollViewports
    builderRoot = nil
    builderStack = []
    buildingScrollViewports = []
    activatePending = false
  }
}
