import Foundation

@MainActor
package final class WindowRuntime {
  package init(clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    producer = FrameProducer()
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
  private var processingInput = false
  private var drainingInputs = false
  private let producer: FrameProducer
  package let scheduler: FrameScheduler

  package var content: (any Block)? {
    didSet {
      producer.reset()
      preparedKeyboardInput = false
      scheduler.scrollMomentumActive = false
      scheduler.requestContent()
    }
  }
  package var keyBindings = KeyBindings()
  package var frameObserver: FrameObserver?
  package var context: BlockContext { BlockContext(interaction: interaction) }

  package func resolve(_ input: KeyboardInput) -> ResolvedKeyboardInput? {
    if interaction.tree != nil {
      let previousInput = interaction.input
      producer.refreshRegistrations(
        content, viewport: interaction.viewport.size, context: context,
        keyboardNavigationOverscan: true)
      // Clipboard translation may consult the last pointer position before the
      // resolved event is dispatched; the registration-only input is synthetic.
      interaction.restoreInputAfterRegistration(previousInput)
    }
    return interaction.resolve(input, appBindings: keyBindings)
  }

  /// Resolves and synchronously delivers one native key against one fresh update.
  /// The delivery may translate clipboard events, then call `handleInput` once.
  /// No validity token survives this scope or an intervening input dispatch.
  package func handleKeyboardInput(
    _ input: KeyboardInput, deliver: @escaping @MainActor (ResolvedKeyboardInput) -> Void
  ) {
    guard interaction.tree != nil, !processingInput else {
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
    if input.commands.count + input.textEvents.count > 1 {
      preparedKeyboardInput = false
      pendingInputs.append(contentsOf: input.separateEvents.map { .state($0) })
      drainPendingInputs()
      scheduler.requestContent()
      return
    }
    let refresh = !preparedKeyboardInput
    preparedKeyboardInput = false
    if interaction.tree == nil || processingInput {
      pendingInputs.append(.state(input))
    } else {
      processInput(input, refreshing: refresh)
      drainPendingInputs()
    }
    scheduler.requestContent()
  }

  private func processInput(_ input: InputState, refreshing: Bool = true) {
    processingInput = true
    defer { processingInput = false }
    if refreshing {
      producer.refreshRegistrations(
        content, viewport: interaction.viewport.size, context: context, commands: input.commands)
    }
    interaction.processInput(input)
    interaction.finishInput()
  }

  private func drainPendingInputs() {
    guard !drainingInputs, !processingInput else { return }
    drainingInputs = true
    defer { drainingInputs = false }
    while !pendingInputs.isEmpty, interaction.tree != nil {
      switch pendingInputs.removeFirst() {
      case .state(let input): handleInput(input)
      case .keyboard(let input, let deliver): handleKeyboardInput(input, deliver: deliver)
      }
    }
  }

  package func renderScheduled(
    _ kind: FrameScheduler.FrameKind,
    viewport: Size,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    interaction.viewport = Rect(origin: .zero, size: viewport)
    flushInput()
    _ = interaction.consumeRedrawRequest()
    while !pendingInputs.isEmpty {
      if interaction.tree == nil {
        producer.refreshRegistrations(content, viewport: viewport, context: context)
      }
      drainPendingInputs()
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
    if processingInput, input != InputState() {
      interaction.viewport = Rect(origin: .zero, size: viewport)
      handleInput(input)
      return renderScheduled(.content, viewport: viewport, onChange: onChange)
    }
    return producer.render(
      content: content, viewport: viewport, input: input, context: context,
      processingInput: false, onChange: onChange)
  }

  package func observe(_ list: DrawList, viewport: Size, rasterScale: Point? = nil) {
    frameObserver?(FrameObservation(drawList: list, viewport: viewport, rasterScale: rasterScale))
  }
}
