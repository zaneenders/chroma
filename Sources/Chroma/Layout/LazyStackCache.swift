import Observation
import Synchronization

final class LazyRowIdentity {}

struct LazyMeasurementEnvironment: Equatable {
  var textScale: Float
  var fontMetrics: FontMetrics
  var theme: ChromaTheme
}

struct LazyStackCache {
  var structuralPath: StructuralPath?
  var width: Float?
  var environment: LazyMeasurementEnvironment?
  var rowKeys: [StructuralKey] = []
  var identities: [LazyRowIdentity] = []
  var measurements: [LazyRowMeasurement] = []
  var layout: Interaction.ScrollLayout?
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
    let delivered = invalidationDelivered
    return validity.valid.withLock { $0 } && !delivered
  }

  init(measure: () -> Size) {
    size = .zero
    let validity = validity
    let subscription = FrameTrackingSubscription(
      { [weak self] in self?.invalidationDelivered = true },
      metricsLifetime: PipelineMetrics.trackObservationLifetime())
    self.subscription = subscription
    let enqueue = ObservationDelivery.enqueue
    size = withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      return measure()
    } onChange: { event in
      event.cancel()
      validity.valid.withLock { $0 = false }
      guard let invalidate = subscription.takeCallback() else { return }
      enqueue { invalidate() }
    }
  }

  deinit { subscription?.cancel() }
}
