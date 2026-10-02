import Foundation
import Observation
import Synchronization

final class FrameTrackingSubscription: Observable, Sendable {
  private let metricsLifetime: PipelineMetricLifetime?
  private let registrar = ObservationRegistrar()
  private let callback: Mutex<(@MainActor @Sendable () -> Void)?>

  init(_ onChange: @escaping @MainActor @Sendable () -> Void, metricsLifetime: PipelineMetricLifetime? = nil) {
    self.metricsLifetime = metricsLifetime
    callback = Mutex(onChange)
  }

  var isCancelled: Bool {
    callback.withLock { $0 == nil }
  }

  func trackCancellation() {
    registrar.access(self, keyPath: \.isCancelled)
  }

  func cancel() {
    callback.withLock { $0 = nil }
    registrar.withMutation(of: self, keyPath: \.isCancelled) {}
  }

  func takeCallback() -> (@MainActor @Sendable () -> Void)? {
    callback.withLock { callback in
      defer { callback = nil }
      return callback
    }
  }
}

@MainActor
package final class FrameProducer {
  private var generation: UInt64 = 0
  private var subscription: FrameTrackingSubscription?
  private weak var interaction: Interaction?

  package func reset() {
    interaction?.resetRegistrations()
    interaction = nil
    resetTracking()
  }

  private func resetTracking() {
    generation &+= 1
    subscription?.cancel()
    subscription = nil
  }

  isolated deinit {
    subscription?.cancel()
  }

  package func render(
    content: (any Block)?,
    viewport: Size,
    input: InputState,
    context: BlockContext,
    processingInput: Bool = true,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    resetTracking()
    self.interaction = context.interaction
    let generation = generation
    let interaction = context.interaction
    interaction.viewport = Rect(origin: .zero, size: viewport)
    if interaction.tree == nil {
      let editingLeaf = interaction.editingLeaf
      let wasEditing = interaction.isTextEditing
      let caret = interaction.caretOffset
      let selection = interaction.textSelectionRange
      refreshRegistrations(content, viewport: viewport, context: context)
      if let editingLeaf, interaction.tree?.findLeaf(editingLeaf) != nil {
        interaction.beginEditing(editingLeaf, caretOffset: caret)
        interaction.textSelectionRange = selection
        if !wasEditing { interaction.stopInput() }
      }
    }
    if !input.textEvents.isEmpty || !input.commands.isEmpty || input.pointerPressed || input.pointerReleased
      || input.scrollDelta != .zero
    {
      refreshRegistrations(content, viewport: viewport, context: context, commands: input.commands)
    }
    interaction.beginFrame(input: input, processingInput: processingInput)
    let subscription = FrameTrackingSubscription(
      onChange, metricsLifetime: PipelineMetrics.trackLifetime(.observationSubscription))
    self.subscription = subscription
    let enqueue = ObservationDelivery.enqueue
    let drawList = withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      var drawList = DrawList()
      var context = context
      context.isPresentationUpdate = true
      if let content {
        let resolved = BlockEngine.resolve(content, context: context)
        let rect = Rect(origin: .zero, size: viewport)
        resolved.register(in: rect)
        resolved.paint(into: &drawList, in: rect)
      }
      return drawList
    } onChange: { [weak self, weak subscription] event in
      event.cancel()
      guard let onChange = subscription?.takeCallback() else { return }
      enqueue { [weak self] in
        guard let self, self.generation == generation else { return }
        onChange()
      }
    }
    interaction.endFrame()
    var result = drawList
    BlockEngine.countDrawingCommands(into: &result) { list in
      interaction.paintNavigation(into: &list, theme: context.theme)
    }
    return result
  }

  package func refreshRegistrations(
    _ content: (any Block)?, viewport: Size, context: BlockContext, commands: [Command] = [],
    keyboardNavigationOverscan: Bool = false
  ) {
    var context = context
    context.keyboardNavigationOverscan = keyboardNavigationOverscan
    context.isPresentationUpdate = false
    let interaction = context.interaction
    interaction.refreshingRegistrations = interaction.tree != nil
    interaction.beginFrame(input: InputState(commands: commands))
    interaction.refreshingRegistrations = true
    defer { interaction.refreshingRegistrations = false }
    if let content {
      BlockEngine.register(content, in: Rect(origin: .zero, size: viewport), context: context)
    }
    interaction.endFrame()
  }

}
