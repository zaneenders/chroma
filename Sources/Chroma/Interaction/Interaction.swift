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
  @ObservationIgnored var nextAnimationDeadline: Double?

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
  package private(set) var editingSessionGeneration: Int = 0

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
  struct ScopedCommandHandler {
    var path: [Int]
    var command: Command
    var action: @MainActor () -> CommandResult
  }
  struct ScopedKeyBindings {
    var path: [Int]
    var bindings: KeyBindings
  }
  struct ScopedActionRole {
    var path: [Int]
    var role: ActionRole
    var action: @MainActor () -> Void
  }

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
    guard editingLeaf != nil, let range = textSelectionRange, let editingText else { return nil }
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
    if editingLeaf != nil, let editingText {
      caretOffset = editingText.count
      textSelectionRange = editingText.isEmpty ? nil : 0..<editingText.count
      return
    }
    if onSelectAll?() == true { return }
    textSelection.selectAll(at: point)
  }

  struct PendingFocus: Equatable {
    var leaf: WidgetID
    var scrollID: WidgetID
  }

  @ObservationIgnored var pendingFocus: PendingFocus?

  struct ScrollState {
    var offset = Point.zero
    var limit = Point.zero
    var pendingReveal: Rect?
    var rows: [WidgetID: Rect] = [:]
    var rowKeys: [WidgetID: StructuralKey] = [:]
    var layout: ScrollLayout?

    mutating func clampOffset() {
      offset.x = min(max(0, offset.x), limit.x)
      offset.y = min(max(0, offset.y), limit.y)
    }
  }

  @ObservationIgnored var scrollStates: [WidgetID: ScrollState] = [:]

  struct ScrollLayout: Equatable {
    enum Rows: Equatable {
      case uniform(count: Int, height: Float, keys: [StructuralKey]?)
      case variable(VariableScrollRows)

      static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.uniform(a, h, k), .uniform(b, j, l)): a == b && h == j && k == l
        case let (.variable(a), .variable(b)): a === b
        default: false
        }
      }
    }

    var width: Float
    var spacing: Float
    var rows: Rows

    func index(of key: StructuralKey) -> Int? {
      switch rows {
      case .uniform(let count, _, let keys):
        if let keys { return keys.firstIndex(of: key) }
        guard let index = key.value as? Int, index >= 0, index < count else { return nil }
        return index
      case .variable(let rows): return rows.keys.firstIndex(of: key)
      }
    }

    func position(of index: Int) -> Float {
      switch rows {
      case .uniform(_, let height, _): Float(index) * (height + spacing)
      case .variable(let rows): rows.starts[index]
      }
    }
  }

  final class VariableScrollRows {
    let keys: [StructuralKey]
    let starts: [Float]
    let heights: [Float]
    let height: Float

    init(keys: [StructuralKey], heights: [Float], spacing: Float) {
      self.keys = keys
      self.heights = heights
      var starts: [Float] = []
      starts.reserveCapacity(heights.count)
      var y: Float = 0
      for height in heights {
        starts.append(y)
        y += height + spacing
      }
      self.starts = starts
      self.height = heights.isEmpty ? 0 : y - spacing
    }

    func firstRow(endingAtOrAfter top: Float) -> Int {
      var low = 0
      var high = starts.count
      while low < high {
        let mid = low + (high - low) / 2
        if starts[mid] + heights[mid] < top { low = mid + 1 } else { high = mid }
      }
      return low
    }

    func firstRow(startingAfter bottom: Float) -> Int {
      var low = 0
      var high = starts.count
      while low < high {
        let mid = low + (high - low) / 2
        if starts[mid] <= bottom { low = mid + 1 } else { high = mid }
      }
      return low
    }
  }

  var activeCommandPath: [Int] {
    if let selection { return selection }
    if let selected = navigation?.node(at: navigationPath), selected.isGroup {
      if navigationPath.isEmpty, let first = selected.children.first {
        var common = first.renderPath
        for child in selected.children.dropFirst() {
          while !isPrefix(common, of: child.renderPath) { common.removeLast() }
        }
        return common
      }
      return selected.renderPath
    }
    return []
  }

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

  struct FrameRegistrations {
    var commandHandlers: [ScopedCommandHandler] = []
    var keyBindingScopes: [ScopedKeyBindings] = []
    var actionRoles: [ScopedActionRole] = []
    var inputHandlers: [WidgetID: @MainActor () -> Void] = [:]
    var buttonActions: [WidgetID: @MainActor () -> Void] = [:]
    var focusTargets: [ObjectIdentifier: (target: FocusTarget, id: WidgetID)] = [:]
  }

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
    nextAnimationDeadline = nil
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

  func beginEditing(_ id: WidgetID, caretOffset: Int) {
    textSelection.clear()
    editingReadOnly = false
    editingSessionGeneration &+= 1
    editingLeaf = id
    self.caretOffset = caretOffset
    textSelectionRange = nil
    mode = .editing
  }

  func startInput() {
    if !isTextEditing { editingSessionGeneration &+= 1 }
    mode = .editing
  }

  func stopInput() {
    if isTextEditing { editingSessionGeneration &+= 1 }
    mode = .movement
  }

  func endEditing() {
    if editingLeaf != nil { editingSessionGeneration &+= 1 }
    editingLeaf = nil
    editingReadOnly = false
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
    building = FrameRegistrations()
    buildingLogicalSelections = [:]

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

    let root = FocusNode(kind: .group, rect: .zero)
    builderRoot = root
    builderStack = [root]
    builderPath = []
    clipStack = []

    if refreshingRegistrations {
      textSelection.layoutRegistry.clear()
      return
    }

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
    textSelection.layoutRegistry.clear()

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
        moveCursor(to: pressed)
        if let leafID = tree.node(at: pressed)?.leafID {
          selectNavigationLeaf(leafID)
        }
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

  package func endFrame() {
    defer {
      if input.pointerReleased {
        dragOrigin = nil
        textDragAnchor = nil
        textDragViewportRow = nil
      }
    }
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
    caretClock.setActive(editingLeaf != nil && textSelectionRange == nil)
    registrations = building
    logicalSelections = buildingLogicalSelections
    builderRoot = nil
    builderStack = []
    activatePending = false
    enterTextPending = false
    movementTextEvents = []
  }

}

@MainActor
extension Interaction {
  func beginGroup(
    rect: Rect,
    axis: FocusNode.Axis? = nil,
    scrollID: WidgetID? = nil,
    navigationID: WidgetID? = nil,
    navigationName: String? = nil
  ) {
    guard let parent = builderStack.last else {
      preconditionFailure("beginGroup outside of a frame; call beginFrame first")
    }
    let node = FocusNode(
      kind: .group, rect: rect, hitRect: clippedRect(rect), axis: axis, scrollID: scrollID,
      navigationID: navigationID, navigationName: navigationName,
      canBeRevealed: scrollID != nil || (builderStack.last?.canBeRevealed ?? false))
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
    guard let tree, let path = tree.findLeaf(id), tree.node(at: path)?.acceptsFocus == true else {
      return
    }
    moveCursor(to: path)
    if editing {
      beginEditing(id, caretOffset: .max)
    }
  }

  func moveCursor(to path: [Int]) {
    guard let tree, tree.node(at: path) != nil else { return }
    if let navigation, let pathInNavigation = navigation.path(to: path) {
      selectNavigation(pathInNavigation)
      return
    }
  }

  func reveal(_ path: [Int], in tree: FocusNode) {
    guard let target = tree.node(at: path)?.rect else { return }
    for depth in 0...path.count {
      let ancestorPath = Array(path.prefix(depth))
      guard let scrollID = tree.node(at: ancestorPath)?.scrollID else { continue }
      scrollStates[scrollID, default: ScrollState()].pendingReveal = target
    }
  }

  private func isPrefix(_ prefix: [Int], of path: [Int]) -> Bool {
    prefix.count <= path.count && Array(path.prefix(prefix.count)) == prefix
  }

  private func isDescendant(_ path: [Int], of scrollID: WidgetID, in tree: FocusNode) -> Bool {
    path.indices.contains { depth in
      tree.node(at: Array(path.prefix(depth)))?.scrollID == scrollID
    }
  }

  func updateScrollLayout(id: WidgetID, layout: ScrollLayout) {
    if let previous = scrollStates[id]?.layout, previous != layout {
      scrollStates[id, default: ScrollState()].rows = [:]
      scrollStates[id, default: ScrollState()].rowKeys = [:]
      scrollStates[id, default: ScrollState()].pendingReveal = nil
      if pendingFocus?.scrollID == id { pendingFocus = nil }
    }
    scrollStates[id, default: ScrollState()].layout = layout
  }

  package func resolve(_ input: KeyboardInput, appBindings: KeyBindings) -> ResolvedKeyboardInput? {
    appBindings.resolve(input, isTextEditing: isTextEditing) { chord in
      keyBindingCommand(for: chord, isTextEditing: isTextEditing, appBindings: appBindings)
    }
  }

  private func keyBindingCommand(
    for chord: KeyChord, isTextEditing: Bool, appBindings: KeyBindings
  ) -> Command?? {
    for scope
      in registrations.keyBindingScopes
      .filter({ isPrefix($0.path, of: activeCommandPath) })
      .sorted(by: { $0.path.count > $1.path.count })
    {
      if let command = scope.bindings.command(for: chord, isTextEditing: isTextEditing) { return command }
    }
    return appBindings.command(for: chord, isTextEditing: isTextEditing)
  }

  func routePendingCommands() {
    for (index, command) in pendingCommands.enumerated() where !handledCommandIndices.contains(index) {
      if mode == .editing, command == .action(.cancel) || command == .action(.dismiss) {
        stopInput()
        handledCommandIndices.insert(index)
        continue
      }
      if editingLeaf != nil, command == .action(.cancel) || command == .action(.dismiss) {
        endEditing()
        handledCommandIndices.insert(index)
        continue
      }
      let handlers =
        registrations.commandHandlers
        .filter { $0.command == command && isPrefix($0.path, of: activeCommandPath) }
        .sorted { $0.path.count > $1.path.count }
      if handlers.contains(where: { $0.action() == .handled }) {
        handledCommandIndices.insert(index)
        continue
      }
      if case .navigation(let direction) = command,
        moveLogicalSelection(direction)
      {
        handledCommandIndices.insert(index)
        continue
      }
      switch command {
      case .action(.submit):
        actionRole(.defaultAction)?()
      case .action(.cancel), .action(.dismiss):
        if let action = actionRole(.cancel) {
          action()
        } else if mode == .editing {
          endEditing()
        }
      default:
        apply(command)
      }
    }
  }

  func actionRole(_ role: ActionRole) -> (@MainActor () -> Void)? {
    registrations.actionRoles
      .filter { $0.role == role && isPrefix($0.path, of: activeCommandPath) }
      .max { $0.path.count < $1.path.count }?
      .action
  }

  func apply(_ command: Command) {
    guard tree != nil else { return }
    switch command {
    case .application:
      return
    case .editing:
      return
    case .navigation(let command):
      if command == .nextFocus || command == .previousFocus {
        if isTextEditing { endEditing() }
        moveNavigation(command)
        return
      }
      guard mode == .movement else { return }
      if editingLeaf != nil {
        switch command {
        case .left: movementTextEvents.append(.moveCaretLeft)
        case .right: movementTextEvents.append(.moveCaretRight)
        case .up: movementTextEvents.append(.moveCaretUp)
        case .down: movementTextEvents.append(.moveCaretDown)
        case .sectionLeft: movementTextEvents.append(.selectCaretLeft)
        case .sectionRight: movementTextEvents.append(.selectCaretRight)
        case .sectionUp: movementTextEvents.append(.selectCaretUp)
        case .sectionDown: movementTextEvents.append(.selectCaretDown)
        case .stepOut: endEditing()
        case .stepIn, .nextFocus, .previousFocus: break
        }
        return
      }
      moveNavigation(command)
    case .action(.activate):
      guard let tree, let selection, tree.node(at: selection)?.isLeaf == true else { return }
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
    action: (@MainActor () -> Void)? = nil, navigationIgnored: Bool = false
  ) -> ButtonState {
    guard let parent = builderStack.last else {
      preconditionFailure("interactiveBehavior outside of a frame; call beginFrame first")
    }
    parent.children.append(
      FocusNode(
        kind: .leaf(id), rect: rect, hitRect: clippedRect(rect), role: role,
        canBeRevealed: parent.canBeRevealed, navigationIgnored: navigationIgnored))
    if role != .normal, let action {
      building.actionRoles.append(ScopedActionRole(path: builderPath, role: role, action: action))
    }

    let focused = selectedLeafID == id
    let hovered = hoveredLeafID == id
    let held = pressedLeaf == id && input.pointerDown
    if let action { building.buttonActions[id] = action }
    return ButtonState(hovered: hovered, focused: focused, held: held, clicked: activatedLeaf == id)
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
