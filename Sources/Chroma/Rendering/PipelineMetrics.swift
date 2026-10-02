import Synchronization

/// Opt-in work counters for the layout, registration, and painting pipeline.
///
/// Enable these only around a diagnostic or benchmark capture. The disabled path is
/// a Boolean check, without logging or lifetime-token allocation. These metrics do
/// not enable retention: resolved nodes and their measurement caches still belong
/// to a single traversal.
@MainActor
public enum PipelineMetrics {
  /// Enabling starts a fresh capture. Disabling stops recording new work, while
  /// lifetime gauges continue to reflect the release of objects already observed.
  public static var isEnabled = false {
    didSet {
      if isEnabled && !oldValue {
        counters = Snapshot()
        lifetimes = PipelineMetricLifetimes()
      }
    }
  }

  /// Counts since the most recent reset, and current live objects observed during
  /// this capture. Objects created before capture are deliberately not included.
  public static var snapshot: Snapshot {
    var result = counters
    if let lifetimes {
      let live = lifetimes.snapshot
      result.liveResolvedNodes = live.resolvedNodes
      result.liveObservationSubscriptions = live.observationSubscriptions
      result.peakResolvedNodes = live.peakResolvedNodes
      result.peakObservationSubscriptions = live.peakObservationSubscriptions
    }
    return result
  }

  /// Clears work counters and resets peaks to the current live counts. Live-object
  /// gauges are preserved so resetting between frames does not hide subscriptions.
  public static func reset() {
    counters = Snapshot()
    lifetimes?.resetPeaks()
  }

  public struct Snapshot: Equatable, Sendable, Codable {
    public internal(set) var bodyEvaluations = 0
    /// Resolved-node measurement requests, including cache hits.
    public internal(set) var measurements = 0
    public internal(set) var measurementCacheHits = 0
    /// Visits to resolved nodes with an assigned rectangle, in either traversal.
    public internal(set) var placements = 0
    public internal(set) var registrations = 0
    public internal(set) var paints = 0
    /// Commands emitted through the instrumented engine/frame entry points.
    /// Direct writes to an unrelated DrawList are outside the capture boundary.
    public internal(set) var drawingCommands = 0
    public internal(set) var compatibilityFallbacks = 0
    /// Fully qualified primitive types that used the draw-to-register adapter.
    public internal(set) var compatibilityFallbackTypes: [String: Int] = [:]
    /// Traversal-scoped resolved nodes, not a persistent retained-tree size.
    public internal(set) var liveResolvedNodes = 0
    /// Frame observation subscription objects that are still alive.
    public internal(set) var liveObservationSubscriptions = 0
    public internal(set) var peakResolvedNodes = 0
    public internal(set) var peakObservationSubscriptions = 0

    public init() {}
  }

  enum Event {
    case bodyEvaluation
    case measurement
    case measurementCacheHit
    case placement
    case registration
    case paint
    case drawingCommands
    case compatibilityFallback
  }

  static func record(_ event: Event, count: Int = 1) {
    guard isEnabled else { return }
    switch event {
    case .bodyEvaluation: counters.bodyEvaluations += count
    case .measurement: counters.measurements += count
    case .measurementCacheHit: counters.measurementCacheHits += count
    case .placement: counters.placements += count
    case .registration: counters.registrations += count
    case .paint: counters.paints += count
    case .drawingCommands: counters.drawingCommands += count
    case .compatibilityFallback: counters.compatibilityFallbacks += count
    }
  }

  static func recordCompatibilityFallback(_ type: Any.Type) {
    guard isEnabled else { return }
    counters.compatibilityFallbacks += 1
    counters.compatibilityFallbackTypes[String(reflecting: type), default: 0] += 1
  }

  static func trackLifetime(_ kind: PipelineMetricLifetime.Kind) -> PipelineMetricLifetime? {
    guard isEnabled, let lifetimes else { return nil }
    return PipelineMetricLifetime(kind: kind, lifetimes: lifetimes)
  }

  private static var counters = Snapshot()
  private static var lifetimes: PipelineMetricLifetimes?
}

/// A checked-Sendable token allows observation objects to release their diagnostic
/// lifetime on any actor. Synchronization and allocation occur only when enabled.
final class PipelineMetricLifetime: Sendable {
  enum Kind: Sendable {
    case resolvedNode
    case observationSubscription
  }

  private let kind: Kind
  private let lifetimes: PipelineMetricLifetimes

  fileprivate init(kind: Kind, lifetimes: PipelineMetricLifetimes) {
    self.kind = kind
    self.lifetimes = lifetimes
    lifetimes.adjust(kind, by: 1)
  }

  deinit { lifetimes.adjust(kind, by: -1) }
}

private final class PipelineMetricLifetimes: Sendable {
  struct Counts: Sendable {
    var resolvedNodes = 0
    var observationSubscriptions = 0
    var peakResolvedNodes = 0
    var peakObservationSubscriptions = 0
  }

  private let counts = Mutex(Counts())

  var snapshot: Counts { counts.withLock { $0 } }

  func adjust(_ kind: PipelineMetricLifetime.Kind, by delta: Int) {
    counts.withLock { counts in
      switch kind {
      case .resolvedNode:
        counts.resolvedNodes += delta
        counts.peakResolvedNodes = max(counts.peakResolvedNodes, counts.resolvedNodes)
      case .observationSubscription:
        counts.observationSubscriptions += delta
        counts.peakObservationSubscriptions = max(counts.peakObservationSubscriptions, counts.observationSubscriptions)
      }
    }
  }

  func resetPeaks() {
    counts.withLock { counts in
      counts.peakResolvedNodes = counts.resolvedNodes
      counts.peakObservationSubscriptions = counts.observationSubscriptions
    }
  }
}
