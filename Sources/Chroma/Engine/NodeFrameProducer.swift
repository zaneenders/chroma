import Observation

@MainActor
final class NodeFrameProducer {
  private var scene = NodeScene()
  private var subscription: FrameTrackingSubscription?
  private var viewport: Size?
  private var subscriptions: [FrameTrackingSubscription] = []
  private(set) var builds = 0
  private(set) var paints = 0

  func reset() {
    subscription?.cancel()
    subscription = nil
    for subscription in subscriptions { subscription.cancel() }
    subscriptions = []
    viewport = nil
  }

  func clear() {
    reset()
    scene = NodeScene()
  }

  deinit {
    subscription?.cancel()
    for subscription in subscriptions { subscription.cancel() }
  }

  func refresh(
    content: any Block, viewport: Size, context: BlockContext,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) throws {
    guard
      self.viewport != viewport || subscription?.isActive != true
        || subscriptions.contains(where: { !$0.isActive })
    else { return }
    reset()
    let subscription = FrameTrackingSubscription(onChange)
    self.subscription = subscription
    try withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      try scene.update(content, context: context)
      try scene.layout(in: Rect(origin: .zero, size: viewport))
    } onChange: { [weak subscription] event in
      event.cancel()
      if let callback = subscription?.takeCallback() { ObservationDelivery.enqueue(callback) }
    }
    scene.prepare(viewport: viewport)
    self.viewport = viewport
    builds += 1
  }

  func dispatch(_ input: InputState, onChange: @escaping @MainActor @Sendable () -> Void) throws {
    guard input.scrollDelta != .zero else {
      try scene.dispatch(input)
      return
    }
    scene.processInput(input)
    let revision = scene.rowBuildRevision
    let subscription = FrameTrackingSubscription(onChange)
    try withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      try scene.refreshScroll()
    } onChange: { [weak subscription] event in
      event.cancel()
      if let callback = subscription?.takeCallback() { ObservationDelivery.enqueue(callback) }
    }
    scene.prepareIfNeeded()
    if revision != scene.rowBuildRevision {
      for previous in subscriptions { previous.cancel() }
      subscriptions = [subscription]
    } else {
      subscription.cancel()
    }
  }

  func paint() -> DrawList {
    paints += 1
    return scene.paint()
  }
}
