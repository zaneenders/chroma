import Foundation

@MainActor
package final class WindowRuntime {
  package init(clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    producer = FrameProducer(clock: clock)
    scheduler = FrameScheduler(clock: clock)
  }

  package let interaction = Interaction()
  private var inputActions: [@MainActor () -> Void] = []
  private var inputTask: Task<Void, Never>?
  private enum PendingInput {
    case state(InputState, notifyingObservers: Bool)
    case keyboard(KeyboardInput, @MainActor (ResolvedKeyboardInput) -> Void)
  }
  private var pendingInputs: [PendingInput] = []
  private var nextInput = 0
  private var drainingInputs = false
  private var hasViewport = false
  private var preparedKeyboardInput = false
  private let producer: FrameProducer
  package let scheduler: FrameScheduler

  package var build: LayoutBuilder? {
    didSet {
      producer.reset()
      preparedKeyboardInput = false
      scheduler.scrollMomentumActive = false
      scheduler.animationsActive = false
      scheduler.requestContent()
    }
  }

  package var keyBindings = KeyBindings()
  package var frameObserver: FrameObserver?
  package var context: LayoutContext { LayoutContext(interaction: interaction) }

  package func resolve(_ input: KeyboardInput) -> ResolvedKeyboardInput? {
    if interaction.tree != nil {
      let previousInput = interaction.input
      producer.refreshRegistrations(
        build, viewport: interaction.viewport.size, context: context,
        keyboardNavigationOverscan: true)
      // Clipboard translation may consult the last pointer position before the
      // resolved event is dispatched; the registration-only input is synthetic.
      interaction.restoreInputAfterRegistration(previousInput)
      scheduler.animationsActive = interaction.animationsActive
    }
    return interaction.resolve(input, appBindings: keyBindings)
  }

  /// Delivers one native key in input order against one fresh update.
  /// The delivery may translate clipboard events, then call `handleInput` once.
  /// No validity token survives this scope or an intervening input dispatch.
  package func handleKeyboardInput(
    _ input: KeyboardInput, deliver: @escaping @MainActor (ResolvedKeyboardInput) -> Void
  ) {
    pendingInputs.append(.keyboard(input, deliver))
    if !hasViewport { scheduler.requestContent() }
    drainInputs()
  }

  isolated deinit {
    inputTask?.cancel()
    producer.reset()
  }

  package func reset() {
    inputTask?.cancel()
    inputTask = nil
    inputActions = []
    pendingInputs = []
    nextInput = 0
    hasViewport = false
    preparedKeyboardInput = false
    producer.reset()
    scheduler.reset()
  }

  package func dispatchInput(requestsFrame: Bool = true, _ action: @escaping @MainActor () -> Void) {
    inputActions.append(action)
    scheduler.inputPending = true
    if requestsFrame { scheduler.requestContent() }
    guard inputTask == nil else { return }
    inputTask = Task(priority: .userInitiated) { @MainActor [weak self] in
      guard let self, !Task.isCancelled else { return }
      self.flushInput()
      self.inputTask = nil
    }
  }

  private func flushInput() {
    while !inputActions.isEmpty {
      let actions = inputActions
      inputActions.removeAll(keepingCapacity: true)
      for action in actions { action() }
    }
    scheduler.inputPending = false
  }

  package func handleInput(_ input: InputState) {
    if preparedKeyboardInput {
      // Translation is part of the current raw-key event, before later FIFO entries.
      // Clear preparation before dispatch so callbacks enqueue their own input.
      preparedKeyboardInput = false
      processInput(input, refreshing: false)
    } else {
      pendingInputs.append(.state(input, notifyingObservers: true))
      drainInputs()
    }
    scheduler.requestContent()
  }

  private func prepareRegistrations() {
    guard interaction.tree == nil else { return }
    let previousInput = interaction.input
    let editingLeaf = interaction.editingLeaf
    let wasEditing = interaction.isTextEditing
    let caret = interaction.caretOffset
    let selection = interaction.textSelectionRange
    producer.refreshRegistrations(build, viewport: interaction.viewport.size, context: context)
    interaction.restoreInputAfterRegistration(previousInput)
    if let editingLeaf, interaction.tree?.findLeaf(editingLeaf) != nil {
      interaction.beginEditing(editingLeaf, caretOffset: caret)
      interaction.textSelectionRange = selection
      if !wasEditing { interaction.stopInput() }
    }
  }

  private func drainInputs() {
    guard hasViewport, !drainingInputs else { return }
    drainingInputs = true
    defer {
      pendingInputs.removeAll(keepingCapacity: true)
      nextInput = 0
      drainingInputs = false
    }
    while hasViewport, nextInput < pendingInputs.count {
      let pending = pendingInputs[nextInput]
      nextInput += 1
      prepareRegistrations()
      switch pending {
      case .state(let input, let notifyingObservers):
        processInput(input, notifyingObservers: notifyingObservers)
      case .keyboard(let input, let deliver):
        guard let resolved = resolve(input) else { continue }
        preparedKeyboardInput = true
        deliver(resolved)
        preparedKeyboardInput = false
      }
    }
  }

  private func processInput(_ input: InputState, refreshing: Bool = true, notifyingObservers: Bool = true) {
    // Hover can use the last frame's geometry. Actionable events need current callbacks
    // and layout, including between events whose presentation is coalesced.
    if refreshing && input.isActionable {
      producer.refreshRegistrations(
        build, viewport: interaction.viewport.size, context: context, commands: input.commands)
    }
    interaction.processInput(input, notifyingObservers: notifyingObservers)
    interaction.finishInput()
    scheduler.animationsActive = interaction.animationsActive
  }

  package func renderScheduled(
    _ kind: FrameScheduler.FrameKind,
    viewport: Size,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    render(viewport: viewport, input: interaction.input.settled, processingInput: false, onChange: onChange)
  }

  package func render(
    viewport: Size,
    input: InputState,
    processingInput: Bool = true,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    interaction.viewport = Rect(origin: .zero, size: viewport)
    hasViewport = true
    flushInput()
    if processingInput {
      pendingInputs.append(.state(input, notifyingObservers: input != InputState()))
    }
    drainInputs()
    prepareRegistrations()
    _ = interaction.consumeRedrawRequest()
    scheduler.consumeContentRequest()
    // Read the root and settled state after dispatch: actions may replace either.
    let list = producer.render(
      build: build, viewport: viewport, input: interaction.input.settled, context: context, onChange: onChange)
    scheduler.animationsActive = interaction.animationsActive
    return list
  }

  package func observe(_ list: DrawList, viewport: Size, rasterScale: Point? = nil) {
    frameObserver?(FrameObservation(drawList: list, viewport: viewport, rasterScale: rasterScale))
  }
}
