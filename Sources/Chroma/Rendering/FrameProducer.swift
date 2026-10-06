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
  private var onChange: (@MainActor @Sendable () -> Void)?
  private weak var interaction: Interaction?

  package func reset() {
    interaction?.resetRegistrations()
    interaction = nil
    onChange = nil
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
    self.onChange = onChange
    self.interaction = context.interaction
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
    if processingInput, input.commands.count + input.textEvents.count > 1 {
      for event in input.separateEvents {
        refreshRegistrations(content, viewport: viewport, context: context, commands: event.commands)
        interaction.processInput(event)
        interaction.finishInput()
      }
    } else if processingInput, input != InputState() {
      refreshRegistrations(content, viewport: viewport, context: context, commands: input.commands)
    }
    interaction.beginFrame(
      input: input, processingInput: processingInput && input.commands.count + input.textEvents.count <= 1)
    let drawList = track {
      var drawList = DrawList()

      if let content {
        let resolved = BlockEngine.resolve(content, context: context)
        let rect = Rect(origin: .zero, size: viewport)
        resolved.register(in: rect)
        interaction.endFrame()
        resolved.paint(into: &drawList, in: rect)
      } else {
        interaction.endFrame()
      }
      return drawList
    }
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
    self.interaction = context.interaction
    var context = context
    context.keyboardNavigationOverscan = keyboardNavigationOverscan

    let interaction = context.interaction
    track {
      interaction.refreshingRegistrations = true
      interaction.beginFrame(input: InputState(commands: commands), processingInput: false)
      defer { interaction.refreshingRegistrations = false }
      if let content {
        BlockEngine.register(content, in: Rect(origin: .zero, size: viewport), context: context)
      }
      interaction.endFrame()
    }
  }

  private func track<Output>(_ body: () -> Output) -> Output {
    resetTracking()
    guard let onChange else { return body() }
    let generation = generation
    let subscription = FrameTrackingSubscription(
      onChange, metricsLifetime: PipelineMetrics.trackLifetime(.observationSubscription))
    self.subscription = subscription
    let enqueue = ObservationDelivery.enqueue
    return withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      return body()
    } onChange: { [weak self, weak subscription] event in
      event.cancel()
      guard let onChange = subscription?.takeCallback() else { return }
      enqueue { [weak self] in
        guard let self, self.generation == generation else { return }
        self.onChange = nil
        onChange()
      }
    }
  }

}
