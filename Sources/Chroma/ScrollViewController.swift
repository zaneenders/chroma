import Dispatch
import Observation
import Synchronization

enum ScrollRequest: Equatable, Sendable {
  case top
  case bottom
  case offset(Float)
  case visible(Rect)
}

@Observable
@MainActor
public final class ScrollViewController {
  var request: ScrollRequest?
  @ObservationIgnored var lazyStackCache = LazyStackCache()

  public init() {}
  public func scrollToTop() { request = .top }
  public func scrollToBottom() { request = .bottom }
  public func scroll(to offset: Float) { request = .offset(offset) }
  public func scrollToVisible(_ rect: Rect) { request = .visible(rect) }
}

final class LazyRowIdentity {}

struct LazyMeasurementEnvironment: Equatable {
  var textScale: Float
  var fontMetrics: FontMetrics
  var theme: ChromaTheme
}

struct LazyStackCache {
  var width: Float?
  var environment: LazyMeasurementEnvironment?
  var rowIDs: [WidgetID] = []
  var identities: [LazyRowIdentity] = []
  var measurements: [LazyRowMeasurement] = []
  @MainActor var rowSizes: [Size] { measurements.map(\.size) }
}

private final class LazyMeasurementValidity: Sendable {
  let valid = Mutex(true)
}

@Observable
@MainActor
final class LazyRowMeasurement {
  private(set) var size: Size
  private var invalidationDelivered = false
  @ObservationIgnored private let validity = LazyMeasurementValidity()
  @ObservationIgnored private var subscription: FrameTrackingSubscription?

  var valid: Bool {
    // Always track delivery, even when the synchronous dirty bit is already set.
    let delivered = invalidationDelivered
    return validity.valid.withLock { $0 } && !delivered
  }

  init(measure: () -> Size) {
    size = .zero
    let validity = validity
    let subscription = FrameTrackingSubscription { [weak self] in self?.invalidationDelivered = true }
    self.subscription = subscription
    size = withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      return measure()
    } onChange: { event in
      event.cancel()
      // Observation can fire on any executor. Invalidate before a synchronous render
      // can reuse the size; deliver observable redraw demand on the main actor.
      validity.valid.withLock { $0 = false }
      guard let invalidate = subscription.takeCallback() else { return }
      DispatchQueue.main.async { invalidate() }
    }
  }

  deinit { subscription?.cancel() }
}
