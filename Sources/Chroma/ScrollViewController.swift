import Dispatch
import Observation

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

@Observable
@MainActor
final class LazyRowMeasurement {
  private(set) var size: Size
  private(set) var valid = true
  @ObservationIgnored private var subscription: FrameTrackingSubscription?

  init(measure: () -> Size) {
    size = .zero
    let subscription = FrameTrackingSubscription { [weak self] in self?.valid = false }
    self.subscription = subscription
    size = withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      return measure()
    } onChange: { event in
      event.cancel()
      guard let invalidate = subscription.takeCallback() else { return }
      DispatchQueue.main.async { invalidate() }
    }
  }

  deinit { subscription?.cancel() }
}
