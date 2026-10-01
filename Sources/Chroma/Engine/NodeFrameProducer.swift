import Observation

@MainActor
final class NodeFrameProducer {
  private var scene = NodeScene()
  private var subscription: FrameTrackingSubscription?
  private var viewport: Size?
  private var metrics: FontMetrics?
  private(set) var builds = 0
  private(set) var paints = 0
  var measurements: Int { scene.measurements }
  var layouts: Int { scene.layouts }
  var preparations: Int { scene.preparations }

  func reset() {
    subscription?.cancel()
    subscription = nil
    scene.resetTracking()
    viewport = nil
    metrics = nil
  }

  func clear() {
    reset()
    scene = NodeScene()
  }

  deinit {
    subscription?.cancel()
  }

  func refresh(
    content: any Block, viewport: Size, context: BlockContext,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) throws {
    let needsBuild = subscription?.isActive != true || !scene.rowsAreValid
    guard needsBuild || self.viewport != viewport || metrics != context.fontMetrics else { return }
    if needsBuild {
      reset()
      let subscription = FrameTrackingSubscription(onChange)
      self.subscription = subscription
      try withObservationTracking(options: .didSet) {
        subscription.trackCancellation()
        try scene.update(content, context: context)
      } onChange: { [weak subscription] event in
        event.cancel()
        if let callback = subscription?.takeCallback() { ObservationDelivery.enqueue(callback) }
      }
      builds += 1
    }
    scene.onChange = onChange
    try scene.layout(in: Rect(origin: .zero, size: viewport))
    scene.prepareIfNeeded(viewport: viewport)
    self.viewport = viewport
    metrics = context.fontMetrics
  }

  func dispatch(_ input: InputState, onChange: @escaping @MainActor @Sendable () -> Void) throws {
    scene.processInput(input)
    scene.onChange = onChange
    try scene.refreshScroll()
    scene.prepareIfNeeded()
  }

  func paint() -> DrawList {
    paints += 1
    return scene.paint()
  }
}
