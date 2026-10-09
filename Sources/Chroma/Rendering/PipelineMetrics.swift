import Synchronization

/// Opt-in work counters for the layout, registration, and painting pipeline.
///
/// Enable these only around a diagnostic or benchmark capture. The disabled path is
/// a Boolean check, without logging or lifetime-token allocation.
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
      result.liveObservationSubscriptions = live.observationSubscriptions
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
    /// Records emitted into typed buffers, including custom extension records.
    public internal(set) var layoutNodes = 0
    /// Buffer capacity growth events; this is not a process allocation count.
    public internal(set) var bufferGrowths = 0
    /// Resolved-node measurement requests, including cache hits.
    public internal(set) var measurements = 0
    public internal(set) var measurementCacheHits = 0
    /// Immutable text line-layout snapshots prepared for built-in text controls.
    public internal(set) var textLayouts = 0
    /// Visits to resolved nodes with an assigned rectangle, in either traversal.
    public internal(set) var placements = 0
    public internal(set) var registrations = 0
    public internal(set) var paints = 0
    /// Commands emitted through the instrumented engine/frame entry points.
    /// Direct writes to an unrelated DrawList are outside the capture boundary.
    public internal(set) var drawingCommands = 0
    /// Frame and row observation subscriptions that are still alive.
    public internal(set) var liveObservationSubscriptions = 0
    public internal(set) var peakObservationSubscriptions = 0

    public init() {}
  }

  enum Event {
    case layoutNode
    case bufferGrowth
    case measurement
    case measurementCacheHit
    case textLayout
    case placement
    case registration
    case paint
    case drawingCommands
  }

  static func record(_ event: Event, count: Int = 1) {
    guard isEnabled else { return }
    switch event {
    case .layoutNode: counters.layoutNodes += count
    case .bufferGrowth: counters.bufferGrowths += count
    case .measurement: counters.measurements += count
    case .measurementCacheHit: counters.measurementCacheHits += count
    case .textLayout: counters.textLayouts += count
    case .placement: counters.placements += count
    case .registration: counters.registrations += count
    case .paint: counters.paints += count
    case .drawingCommands: counters.drawingCommands += count
    }
  }

  static func trackObservationLifetime() -> PipelineMetricLifetime? {
    guard isEnabled, let lifetimes else { return nil }
    return PipelineMetricLifetime(lifetimes: lifetimes)
  }

  private static var counters = Snapshot()
  private static var lifetimes: PipelineMetricLifetimes?
}

/// A checked-Sendable token allows observation objects to release their diagnostic
/// lifetime on any actor. Synchronization and allocation occur only when enabled.
final class PipelineMetricLifetime: Sendable {
  private let lifetimes: PipelineMetricLifetimes

  fileprivate init(lifetimes: PipelineMetricLifetimes) {
    self.lifetimes = lifetimes
    lifetimes.adjust(by: 1)
  }

  deinit { lifetimes.adjust(by: -1) }
}

private final class PipelineMetricLifetimes: Sendable {
  struct Counts: Sendable {
    var observationSubscriptions = 0
    var peakObservationSubscriptions = 0
  }

  private let counts = Mutex(Counts())

  var snapshot: Counts { counts.withLock { $0 } }

  func adjust(by delta: Int) {
    counts.withLock { counts in
      counts.observationSubscriptions += delta
      counts.peakObservationSubscriptions = max(counts.peakObservationSubscriptions, counts.observationSubscriptions)
    }
  }

  func resetPeaks() {
    counts.withLock { counts in
      counts.peakObservationSubscriptions = counts.observationSubscriptions
    }
  }
}
