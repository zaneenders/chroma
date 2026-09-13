import Dispatch
import Observation
import Synchronization

private final class FrameTrackingSubscription: Sendable {
  private let callback: Mutex<(@MainActor @Sendable () -> Void)?>

  init(_ onChange: @escaping @MainActor @Sendable () -> Void) {
    callback = Mutex(onChange)
  }

  func cancel() {
    callback.withLock { $0 = nil }
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

  package init() {}

  package func reset() {
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
    reset()
    let generation = generation
    let interaction = context.interaction
    interaction.beginFrame(input: input)
    let subscription = FrameTrackingSubscription(onChange)
    self.subscription = subscription
    let drawList = withObservationTracking(options: .didSet) {
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
    return drawList
  }
}
