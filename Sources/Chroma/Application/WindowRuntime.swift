import Foundation

@MainActor
package final class WindowRuntime {
  package init(clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    nodeProducer = NodeFrameProducer(clock: clock)
    scheduler = FrameScheduler(clock: clock)
  }

  package let interaction = Interaction()
  private let nodeProducer: NodeFrameProducer
  private var nodeViewport: Size?
  private var nodeOnChange: @MainActor @Sendable () -> Void = {}
  package var nodeBuilds: Int { nodeProducer.builds }
  package var nodePaints: Int { nodeProducer.paints }

  private func refreshNodes(forceEditorText: Bool = false) -> Bool {
    guard let content, let nodeViewport else {
      return false
    }
    do {
      try nodeProducer.refresh(
        content: content, viewport: nodeViewport, context: context, forceEditorText: forceEditorText,
        onChange: nodeOnChange)
      scheduler.animationsActive = nodeProducer.needsAnimationFrame
      return true
    } catch {
      preconditionFailure("Content must support the retained lifecycle: \(error)")
    }
  }

  private var inputActions: [@MainActor () -> Void] = []
  private var inputTask: Task<Void, Never>?
  private var pendingInputs: [InputState] = []
  package let scheduler: FrameScheduler

  package var content: (any Block)? {
    didSet {
      nodeProducer.clear()
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
  package var needsAnimationFrame: Bool { nodeProducer.needsAnimationFrame }
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
    nodeProducer.clear()
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
      do { try nodeProducer.dispatch(input, onChange: nodeOnChange) } catch {
        preconditionFailure("Input content must support the retained lifecycle: \(error)")
      }
    } else {
      pendingInputs.append(input)
    }
    scheduler.animationsActive = needsAnimationFrame
    scheduler.requestContent()
  }

  package func renderScheduled(
    _ kind: FrameScheduler.FrameKind,
    viewport: Size,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    flushInput()
    if kind == .animation && !scheduler.hasContentRequest && nodeViewport == viewport {
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
    scheduler.consumeContentRequest()
    return DrawList()
  }

  package func render(
    viewport: Size,
    input: InputState,
    processingInput: Bool = true,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    nodeProducer.invalidateContent()
    nodeViewport = viewport
    nodeOnChange = onChange
    if refreshNodes(forceEditorText: true) {
      if processingInput {
        handleInput(input)
        _ = refreshNodes()
      }
      return paintNodes()
    }
    return DrawList()
  }

  private func paintNodes() -> DrawList {
    var list = nodeProducer.paint()
    if !list.commands.isEmpty { interaction.paintNavigation(into: &list, theme: context.theme) }
    scheduler.animationsActive = nodeProducer.needsAnimationFrame
    return list
  }

  package func renderAnimations() -> DrawList {
    var list = nodeProducer.renderAnimations()
    if !list.commands.isEmpty { interaction.paintNavigation(into: &list, theme: context.theme) }
    scheduler.animationsActive = needsAnimationFrame
    return list
  }

  package func observe(_ list: DrawList, viewport: Size, rasterScale: Point? = nil) {
    frameObserver?(FrameObservation(drawList: list, viewport: viewport, rasterScale: rasterScale))
  }
}
