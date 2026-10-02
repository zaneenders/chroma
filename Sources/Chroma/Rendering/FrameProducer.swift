import Foundation
import Observation
import Synchronization

final class FrameTrackingSubscription: Observable, Sendable {
  private let registrar = ObservationRegistrar()
  private let callback: Mutex<(@MainActor @Sendable () -> Void)?>

  init(_ onChange: @escaping @MainActor @Sendable () -> Void) {
    callback = Mutex(onChange)
  }

  private var isCancelled: Bool {
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

  deinit { subscription?.cancel() }

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
    let subscription = FrameTrackingSubscription(onChange)
    self.subscription = subscription
    let enqueue = ObservationDelivery.enqueue
    let drawList = withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      var drawList = DrawList()
      if let content {
        BlockEngine.draw(
          content, into: &drawList, in: Rect(origin: .zero, size: viewport), context: context)
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
    interaction.paintNavigation(into: &result, theme: context.theme)
    return result
  }

  package func refreshRegistrations(
    _ content: (any Block)?, viewport: Size, context: BlockContext, commands: [Command] = []
  ) {
    let interaction = context.interaction
    interaction.refreshingRegistrations = interaction.tree != nil
    interaction.beginFrame(input: InputState(commands: commands))
    interaction.refreshingRegistrations = true
    defer { interaction.refreshingRegistrations = false }
    var discarded = DrawList()
    if let content {
      BlockEngine.draw(content, into: &discarded, in: Rect(origin: .zero, size: viewport), context: context)
    }
    interaction.endFrame()
  }

}
