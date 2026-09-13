import Dispatch
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

  private let clock: @MainActor () -> Double
  package private(set) var needsAnimationFrame = false

  package init(clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    self.clock = clock
  }

  package func reset() {
    needsAnimationFrame = false
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
    context: RenderContext,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    resetTracking()
    self.interaction = context.interaction
    let generation = generation
    let interaction = context.interaction
    interaction.animationFrame = AnimationFrame(timestamp: clock())
    if interaction.tree == nil {
      // Bootstrap hit geometry without delivering input or executing actions.
      let editingLeaf = interaction.editingLeaf
      let caret = interaction.caretOffset
      let selection = interaction.textSelectionRange
      interaction.beginFrame(input: InputState())
      var bootstrap = DrawList()
      if let content {
        BlockEngine.draw(content, into: &bootstrap, in: Rect(origin: .zero, size: viewport), context: context)
      }
      interaction.endFrame()
      if let editingLeaf, interaction.tree?.findLeaf(editingLeaf) != nil {
        interaction.beginEditing(editingLeaf, caretOffset: caret)
        interaction.textSelectionRange = selection
      }
    }
    interaction.animationRequested = false
    interaction.beginFrame(input: input)
    let subscription = FrameTrackingSubscription(onChange)
    self.subscription = subscription
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
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == generation else { return }
        onChange()
      }
    }
    interaction.endFrame()
    needsAnimationFrame = interaction.animationRequested
    return drawList
  }
}
