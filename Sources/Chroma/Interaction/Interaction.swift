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
  @ObservationIgnored var animationPaints: [AnimationPaint] = []

  package let textSelection = TextSelectionManager()

  package var fontMetrics = FontMetrics()

  @ObservationIgnored package private(set) var input = InputState()

  @ObservationIgnored package var frameRate: Double = 0

  package internal(set) var selection: [Int]?
  @ObservationIgnored var navigation: NavigationNode?
  @ObservationIgnored var navigationPath: [Int] = []
  @ObservationIgnored var rememberedNavigation: [WidgetID: WidgetID] = [:]
  struct LogicalSelectionRegistration {
    let scrollID: WidgetID
    let selectedKey: @MainActor () -> StructuralKey?
    let select: @MainActor (StructuralKey) -> Void
    let move: @MainActor (Int) -> StructuralKey?
    let reveal: @MainActor (StructuralKey) -> Void
  }
  @ObservationIgnored var logicalSelections: [WidgetID: LogicalSelectionRegistration] = [:]
  @ObservationIgnored var buildingLogicalSelections: [WidgetID: LogicalSelectionRegistration] = [:]

  @ObservationIgnored var viewport: Rect = .zero

  @ObservationIgnored var tree: FocusNode?

  package internal(set) var editingLeaf: WidgetID?
  package internal(set) var editingSessionGeneration: Int = 0

  package internal(set) var caretOffset: Int = 0
  package internal(set) var textSelectionRange: Range<Int>?
  @ObservationIgnored var textDragAnchor: Int?
  @ObservationIgnored var textDragViewportRow: Int?
  package internal(set) var editingText: String?
  package var editingReadOnly = false
  package var acceptsTextInsertion: Bool { isTextEditing && !editingReadOnly }

  public package(set) var mode: InteractionMode = .movement
  package var isTextEditing: Bool { mode == .editing }

  @ObservationIgnored var enterTextPending = false
  @ObservationIgnored var movementTextEvents: [TextEditEvent] = []
  @ObservationIgnored var activatePending = false
  @ObservationIgnored private var redrawRequested = false
  @ObservationIgnored package var onRedrawRequested: (() -> Void)?
  @ObservationIgnored var pendingCommands: [Command] = []
  @ObservationIgnored var handledCommandIndices: Set<Int> = []
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

  struct PendingFocus: Equatable {
    var leaf: WidgetID
    var scrollID: WidgetID
  }

  @ObservationIgnored var pendingFocus: PendingFocus?

  @ObservationIgnored var scrollStates: [WidgetID: ScrollState] = [:]

  @ObservationIgnored var clipStack: [Rect] = []

  package struct LeafState: Equatable, Sendable {
    var selected: WidgetID?
    var hovered: WidgetID?
    var pressed: WidgetID?
  }

  @ObservationIgnored private var leafState = LeafState()
  package var untrackedLeafState: LeafState { leafState }

  var pressedLeaf: WidgetID? {
    get { leafState.pressed }
    set { leafState.pressed = newValue }
  }

  var selectedLeafID: WidgetID? {
    get { leafState.selected }
    set { leafState.selected = newValue }
  }

  var hoveredLeafID: WidgetID? {
    get { leafState.hovered }
    set { leafState.hovered = newValue }
  }

  @ObservationIgnored var builderRoot: FocusNode?
  @ObservationIgnored var builderStack: [FocusNode] = []
  @ObservationIgnored var builderPath: [Int] = []

  @ObservationIgnored var activatedLeaf: WidgetID?

  @ObservationIgnored var registrations = FrameRegistrations()
  @ObservationIgnored var building = FrameRegistrations()

  package init() {}

  func resetRegistrations() {
    for binding in registrations.focusTargets.values {
      binding.target.boundID = nil
      binding.target.interaction = nil
      binding.target.pendingEditing = nil
    }

    registrations = FrameRegistrations()
    building = FrameRegistrations()
    textSelection.clear()
    textSelection.layoutRegistry.clear()
    pendingFocus = nil
    scrollStates = [:]
    animationPaints = []
    tree = nil
    navigation = nil
    navigationPath = []
    rememberedNavigation = [:]
    logicalSelections = [:]
    buildingLogicalSelections = [:]
    selection = nil
    selectedLeafID = nil
    pressedLeaf = nil

    caretClock.setActive(false)
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

  package func beginFrame(input: InputState, processingInput: Bool = true) {
    building = FrameRegistrations()
    buildingLogicalSelections = [:]

    if processingInput { processInput(input) } else { self.input = input }
    let root = FocusNode(kind: .group, rect: .zero)
    builderRoot = root
    builderStack = [root]
    builderPath = []
    clipStack = []
    textSelection.layoutRegistry.clear()
  }

  package func processInput(_ input: InputState) {
    self.input = input
    activatePending = false
    enterTextPending = false
    movementTextEvents = []
    if !refreshingRegistrations {
      pendingCommands = input.commands
      handledCommandIndices = []
      routePendingCommands()
      pendingCommands = []
    }

    activatedLeaf = nil

    if refreshingRegistrations { return }

    if input.pointerPressed {
      dragOrigin = input.pointerPressPosition
      dragCurrent = input.pointerPosition
      textDragAnchor = nil
      textDragViewportRow = nil
      textSelection.clear()
    } else if input.pointerReleased {
      dragCurrent = input.pointerPosition
    } else if isDragging {
      dragCurrent = input.pointerPosition
    }
    textSelection.updateFromDrag(interaction: self)

    defer {
      selectedLeafID = selection.flatMap { tree?.node(at: $0)?.leafID }
      if let editingLeaf, editingLeaf != selectedLeafID {
        endEditing()
      }
      lastPointerPosition = input.pointerPosition
      for handler in registrations.inputHandlers.values { handler() }
      if activatePending, let id = selectedLeafID {
        activatePending = false
        activatedLeaf = id
        registrations.buttonActions[id]?()
      }
    }

    guard let tree else { return }
    let hovered = tree.hitTest(input.pointerPosition)
    hoveredLeafID = hovered.flatMap { tree.node(at: $0)?.leafID }
    if input.pointerPressed {
      let pressed = tree.hitTest(input.pointerPressPosition)
      if let pressed {
        moveCursor(to: pressed, revealing: false)
        pressedLeaf = tree.node(at: pressed)?.leafID
      } else {
        endEditing()
      }
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

  package func finishInput() {
    if input.pointerReleased {
      dragOrigin = nil
      textDragAnchor = nil
      textDragViewportRow = nil
    }
  }

  package func endFrame() {
    defer { finishInput() }
    if !refreshingRegistrations { routePendingCommands() }
    guard let newTree = builderRoot else { return }

    if let editingLeaf, newTree.findLeaf(editingLeaf) == nil { endEditing() }
    if let pressedLeaf, newTree.findLeaf(pressedLeaf) == nil { self.pressedLeaf = nil }
    scrollStates = scrollStates.filter { building.inputHandlers[$0.key] != nil }
    textSelection.reconcile()
    tree = newTree
    reconcileNavigation(in: newTree)
    reconcileLogicalSelection(in: newTree)
    resolveFocusTargets()
    hoveredLeafID = newTree.hitTest(input.pointerPosition).flatMap { newTree.node(at: $0)?.leafID }

    if let pending = pendingFocus {
      if let path = newTree.findLeaf(pending.leaf), newTree.node(at: path)?.acceptsFocus == true,
        isDescendant(path, of: pending.scrollID, in: newTree)
      {
        pendingFocus = nil
        selection = path
        selectedLeafID = pending.leaf
        if let navigationPath = navigation?.path(to: path) {
          self.navigationPath = navigationPath
          if let navigation { rememberNavigation(navigationPath, in: navigation) }
        }
      } else if scrollStates[pending.scrollID]?.pendingReveal == nil {
        pendingFocus = nil
      }
    }

    selectedLeafID = selection.flatMap { newTree.node(at: $0)?.leafID }
    if let editingLeaf, editingLeaf != selectedLeafID { endEditing() }
    caretClock.setActive(editingLeaf != nil && textSelectionRange == nil, timestamp: animationFrame.timestamp)
    registrations = building
    logicalSelections = buildingLogicalSelections
    builderRoot = nil
    builderStack = []
    activatedLeaf = nil
    activatePending = false
    enterTextPending = false
    movementTextEvents = []
  }

  private func isDescendant(_ path: [Int], of scrollID: WidgetID, in tree: FocusNode) -> Bool {
    path.indices.contains { depth in
      tree.node(at: Array(path.prefix(depth)))?.scrollID == scrollID
    }
  }

}
