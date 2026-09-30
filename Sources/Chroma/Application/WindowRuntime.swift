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
  private var pendingInputs: [InputState] = []
  private let producer: FrameProducer
  package let scheduler: FrameScheduler

  package var content: (any Block)? {
    didSet {
      producer.reset()
      reconcileAnimationDemand()
      scheduler.contentAnimationActive = false
      scheduler.requestContent()
    }
  }
  package var keyBindings = KeyBindings()
  package var frameObserver: FrameObserver?
  package var nextAnimationDeadline: Double? { scheduler.animationDeadline }
  package var needsAnimationFrame: Bool { producer.needsAnimationFrame }
  package var context: BlockContext { BlockContext(interaction: interaction) }

  package func resolve(_ input: KeyboardInput) -> ResolvedKeyboardInput? {
    interaction.resolve(input, appBindings: keyBindings)
  }

  deinit { inputTask?.cancel() }

  package func reset() {
    inputTask?.cancel()
    inputTask = nil
    inputActions = []
    pendingInputs = []
    producer.reset()
    scheduler.reset()
    reconcileAnimationDemand()
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
    if interaction.tree == nil {
      pendingInputs.append(input)
    } else {
      processInput(input)
    }
    scheduler.requestContent()
  }

  private func processInput(_ input: InputState) {
    // Presentation can coalesce, but each event needs current callbacks and hit-test geometry.
    producer.refreshRegistrations(
      content, viewport: interaction.viewport.size, context: context, commands: input.commands)
    interaction.processInput(input)
    interaction.finishInput()
  }

  /// Called only once the backend is ready. Input may change demand or cancel this wake-up.
  package func renderScheduled(
    viewport: Size,
    prepareInput: @MainActor () -> Void = {},
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList? {
    flushInput()
    prepareInput()
    flushInput()
    guard let kind = scheduler.takeFrame() else { return nil }
    if kind == .animation { return renderAnimations() }
    return renderContent(viewport: viewport, onChange: onChange)
  }

  package func renderContent(
    viewport: Size,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    _ = interaction.consumeRedrawRequest()
    if !pendingInputs.isEmpty {
      // Establish the viewport, then refresh registrations between queued events too.
      _ = render(viewport: viewport, input: InputState(), onChange: onChange)
      for input in pendingInputs { processInput(input) }
      pendingInputs.removeAll(keepingCapacity: true)
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
    let list = producer.render(
      content: content, viewport: viewport, input: input, context: context,
      processingInput: processingInput, onChange: onChange)
    reconcileAnimationDemand()
    return list
  }

  package func renderAnimations() -> DrawList {
    let list = producer.renderAnimations()
    reconcileAnimationDemand()
    return list
  }

  private func reconcileAnimationDemand() {
    // Paint demand belongs to the producer; full-content animation remains independent.
    scheduler.animationsActive = producer.needsAnimationFrame
  }

  package func observe(_ list: DrawList, viewport: Size, rasterScale: Point? = nil) {
    frameObserver?(FrameObservation(drawList: list, viewport: viewport, rasterScale: rasterScale))
  }
}
