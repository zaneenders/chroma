import Foundation

/// Owns frame demand and timing; backends only gate presentation readiness.
@MainActor
package final class FrameScheduler {
  package enum FrameKind: Sendable { case content, animation }

  package struct ScheduledFrame: Equatable {
    package let deadline: Double
    package let kind: FrameKind
    package let priority: TaskPriority
  }

  private let clock: @MainActor () -> Double
  private var wakeTask: Task<Void, Never>?
  private var scheduled: ScheduledFrame?
  private var isProducing = false
  private var pendingSince: Double?
  package private(set) var lastFrameTime: Double?
  package private(set) var minimumRefreshRate = 30.0
  package private(set) var maximumRefreshRate = 60.0
  package var animationsActive = false { didSet { schedule() } }
  package var contentAnimationActive = false { didSet { schedule() } }
  package var inputPending = false { didSet { schedule() } }
  package var isReady = false { didSet { schedule() } }
  package var onFrame: (@MainActor (FrameKind) -> Void)? { didSet { schedule() } }

  package init(clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    self.clock = clock
  }

  package func setRefreshRates(minimum: Double, maximum: Double) {
    precondition(minimum.isFinite && maximum.isFinite && minimum > 0 && minimum <= maximum && maximum <= 240)
    minimumRefreshRate = minimum
    maximumRefreshRate = maximum
    schedule()
  }

  package func requestContent() {
    if pendingSince == nil { pendingSince = clock() }
    schedule()
  }

  package var hasContentRequest: Bool { pendingSince != nil }

  package var nextFrame: ScheduledFrame? {
    if let pendingSince {
      return ScheduledFrame(
        deadline: lastFrameTime.map { $0 + 1 / maximumRefreshRate } ?? pendingSince,
        kind: .content, priority: .userInitiated)
    }
    guard let animationDeadline else { return nil }
    return ScheduledFrame(
      deadline: animationDeadline,
      kind: contentAnimationActive ? .content : .animation, priority: .utility)
  }

  /// Animation cadence, independent of content demand and backend readiness.
  package var animationDeadline: Double? {
    guard animationsActive || contentAnimationActive, let lastFrameTime else { return nil }
    return lastFrameTime + 1 / minimumRefreshRate
  }

  package func takeFrame() -> FrameKind? {
    let now = clock()
    guard let nextFrame, now >= nextFrame.deadline else { return nil }
    pendingSince = nil
    lastFrameTime = now
    return nextFrame.kind
  }

  package func consumeContentRequest() {
    pendingSince = nil
    schedule()
  }

  package func recordProducedFrame() {
    lastFrameTime = clock()
    schedule()
  }

  package func reset() {
    wakeTask?.cancel()
    wakeTask = nil
    scheduled = nil
    pendingSince = nil
    lastFrameTime = nil
    animationsActive = false
    contentAnimationActive = false
    inputPending = false
  }

  deinit { wakeTask?.cancel() }

  private func schedule() {
    guard !isProducing else { return }
    let next = isReady && !inputPending && onFrame != nil ? nextFrame : nil
    guard next != scheduled else { return }
    wakeTask?.cancel()
    wakeTask = nil
    scheduled = next
    guard let next else { return }
    let delay = max(0, next.deadline - clock())
    wakeTask = Task(priority: next.priority) { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      guard let self, !Task.isCancelled else { return }
      self.wakeTask = nil
      self.scheduled = nil
      if let kind = self.takeFrame() {
        self.isProducing = true
        self.onFrame?(kind)
        self.isProducing = false
        if self.lastFrameTime != nil { self.recordProducedFrame() }
      }
      self.schedule()
    }
  }
}
