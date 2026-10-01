import Foundation

@MainActor
package final class WindowRuntime {
  package init(clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    producer = FrameProducer(clock: clock)
    nodeProducer = NodeFrameProducer(clock: clock)
    scheduler = FrameScheduler(clock: clock)
  }

  package let interaction = Interaction()
  package var nodeLifecycleEnabled = false
  private let nodeProducer: NodeFrameProducer
  private var usingNodes = false
  private var nodeViewport: Size?
  private var nodeOnChange: @MainActor @Sendable () -> Void = {}
  package var nodeBuilds: Int { nodeProducer.builds }
  package var nodePaints: Int { nodeProducer.paints }

  private func refreshNodes(forceEditorText: Bool = false) -> Bool {
    guard nodeLifecycleEnabled, let content, let nodeViewport else {
      usingNodes = false
      return false
    }
    do {
      try nodeProducer.refresh(
        content: content, viewport: nodeViewport, context: context, forceEditorText: forceEditorText,
        onChange: nodeOnChange)
      usingNodes = true
      scheduler.animationsActive = nodeProducer.needsAnimationFrame
      return true
    } catch {
      usingNodes = false
      nodeProducer.reset()
      return false
    }
  }

  private var inputActions: [@MainActor () -> Void] = []
  private var inputTask: Task<Void, Never>?
  private var pendingInputs: [InputState] = []
  private let producer: FrameProducer
  package let scheduler: FrameScheduler

  package var content: (any Block)? {
    didSet {
      usingNodes = false
      nodeProducer.clear()
      producer.reset()
      interaction.resetRegistrations()
      scheduler.animationsActive = false
      scheduler.contentAnimationActive = false
      scheduler.requestContent()
    }
  }
  package var keyBindings = KeyBindings()
  package var frameObserver: FrameObserver?
  package var nextAnimationDeadline: Double? {
    guard needsAnimationFrame, let lastFrameTime = scheduler.lastFrameTime else { return nil }
    return lastFrameTime + 1 / scheduler.minimumRefreshRate
  }
  package var needsAnimationFrame: Bool { usingNodes ? nodeProducer.needsAnimationFrame : producer.needsAnimationFrame }
  package var context: BlockContext { BlockContext(interaction: interaction) }

  package func resolve(_ input: KeyboardInput) -> ResolvedKeyboardInput? {
    _ = refreshNodes()
    return interaction.resolve(input, appBindings: keyBindings)
  }

  deinit { inputTask?.cancel() }

  package func reset() {
    inputTask?.cancel()
    inputTask = nil
    inputActions = []
    pendingInputs = []
    usingNodes = false
    nodeProducer.clear()
    producer.reset()
    interaction.resetRegistrations()
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
    if refreshNodes() {
      do { try nodeProducer.dispatch(input, onChange: nodeOnChange) } catch { nodeProducer.reset() }
    } else if interaction.tree == nil {
      pendingInputs.append(input)
    } else {
      processInput(input)
    }
    scheduler.animationsActive = needsAnimationFrame
    scheduler.requestContent()
  }

  private func processInput(_ input: InputState) {
    let pointerOnly =
      !input.pointerDown && !input.pointerPressed && !input.pointerReleased
      && !interaction.isProcessingDrag && input.scrollDelta == .zero
      && input.commands.isEmpty && input.textEvents.isEmpty
    if !pointerOnly || !producer.registrationsAreValid(viewport: interaction.viewport.size) {
      producer.refreshRegistrations(
        content, viewport: interaction.viewport.size, context: context, commands: input.commands)
    }
    interaction.processInput(input)
    interaction.finishInput()
  }

  package func renderScheduled(
    _ kind: FrameScheduler.FrameKind,
    viewport: Size,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    flushInput()
    if kind == .animation && !scheduler.hasContentRequest && (!usingNodes || nodeViewport == viewport) {
      return renderAnimations()
    }
    _ = interaction.consumeRedrawRequest()
    nodeViewport = viewport
    nodeOnChange = onChange
    if refreshNodes(forceEditorText: true) {
      let inputs = pendingInputs
      pendingInputs.removeAll(keepingCapacity: true)
      for input in inputs { handleInput(input) }
      _ = refreshNodes()
      scheduler.consumeContentRequest()
      return paintNodes()
    }
    if !pendingInputs.isEmpty {
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
    nodeViewport = viewport
    nodeOnChange = onChange
    if refreshNodes(forceEditorText: true) {
      if processingInput {
        handleInput(input)
        _ = refreshNodes()
      }
      return paintNodes()
    }
    let list = producer.render(
      content: content, viewport: viewport, input: input, context: context,
      processingInput: processingInput, onChange: onChange)
    scheduler.animationsActive = producer.needsAnimationFrame
    return list
  }

  private func paintNodes() -> DrawList {
    let list = nodeProducer.paint()
    scheduler.animationsActive = nodeProducer.needsAnimationFrame
    return list
  }

  package func renderAnimations() -> DrawList {
    let list = usingNodes ? nodeProducer.renderAnimations() : producer.renderAnimations()
    scheduler.animationsActive = needsAnimationFrame
    return list
  }

  package func observe(_ list: DrawList, viewport: Size, rasterScale: Point? = nil) {
    frameObserver?(FrameObservation(drawList: list, viewport: viewport, rasterScale: rasterScale))
  }
}
