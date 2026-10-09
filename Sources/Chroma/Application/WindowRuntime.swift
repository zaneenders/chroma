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
    case state(InputState)
    case keyboard(KeyboardInput, @MainActor (ResolvedKeyboardInput) -> Void)
  }
  private var pendingInputs: [PendingInput] = []
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
  package func setContent(_ content: (any Block)?) {
    guard let content else {
      build = nil
      return
    }
    build = { (buffer: inout LayoutBuffer, context: BlockContext) in buffer.emit(content, context: context) }
  }

  package var keyBindings = KeyBindings()
  package var frameObserver: FrameObserver?
  package var context: BlockContext { BlockContext(interaction: interaction) }

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

  /// Resolves and synchronously delivers one native key against one fresh update.
  /// The delivery may translate clipboard events, then call `handleInput` once.
  /// No validity token survives this scope or an intervening input dispatch.
  package func handleKeyboardInput(
    _ input: KeyboardInput, deliver: @escaping @MainActor (ResolvedKeyboardInput) -> Void
  ) {
    guard interaction.tree != nil else {
      pendingInputs.append(.keyboard(input, deliver))
      scheduler.requestContent()
      return
    }
    guard let resolved = resolve(input) else { return }
    preparedKeyboardInput = true
    defer { preparedKeyboardInput = false }
    deliver(resolved)
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
    let refresh = !preparedKeyboardInput
    preparedKeyboardInput = false
    if interaction.tree == nil {
      pendingInputs.append(.state(input))
    } else {
      processInput(input, refreshing: refresh)
    }
    scheduler.requestContent()
  }

  private func processInput(_ input: InputState, refreshing: Bool = true, notifyingObservers: Bool = true) {
    // Hover can use the last frame's geometry. Actionable events need current callbacks
    // and layout, including between events whose presentation is coalesced.
    if refreshing
      && (input.pointerDown || input.pointerPressed || input.pointerReleased || input.scrollDelta != .zero
        || !input.commands.isEmpty || !input.textEvents.isEmpty)
    {
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
    flushInput()
    _ = interaction.consumeRedrawRequest()
    while !pendingInputs.isEmpty {
      let pending = pendingInputs
      pendingInputs.removeAll(keepingCapacity: true)
      for input in pending {
        if interaction.tree == nil {
          _ = render(viewport: viewport, input: InputState(), onChange: onChange)
        }
        switch input {
        case .state(let input): handleInput(input)
        case .keyboard(let input, let deliver): handleKeyboardInput(input, deliver: deliver)
        }
      }
    }
    scheduler.consumeContentRequest()
    var input = interaction.input
    input.pointerPressed = false
    input.pointerReleased = false
    input.scrollDelta = .zero
    input.commands = []
    input.textEvents = []
    return render(viewport: viewport, input: input, processingInput: false, onChange: onChange)
  }

  package func render(
    viewport: Size,
    input: InputState,
    processingInput: Bool = true,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    interaction.viewport = Rect(origin: .zero, size: viewport)
    if interaction.tree == nil {
      let editingLeaf = interaction.editingLeaf
      let wasEditing = interaction.isTextEditing
      let caret = interaction.caretOffset
      let selection = interaction.textSelectionRange
      producer.refreshRegistrations(build, viewport: viewport, context: context)
      if let editingLeaf, interaction.tree?.findLeaf(editingLeaf) != nil {
        interaction.beginEditing(editingLeaf, caretOffset: caret)
        interaction.textSelectionRange = selection
        if !wasEditing { interaction.stopInput() }
      }
    }
    if processingInput { processInput(input, notifyingObservers: input != InputState()) }
    // Read the root after dispatch: an action may have replaced it synchronously.
    let list = producer.render(build: build, viewport: viewport, input: input, context: context, onChange: onChange)
    scheduler.animationsActive = interaction.animationsActive
    return list
  }

  package func observe(_ list: DrawList, viewport: Size, rasterScale: Point? = nil) {
    frameObserver?(FrameObservation(drawList: list, viewport: viewport, rasterScale: rasterScale))
  }
}
