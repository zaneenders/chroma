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
  private enum WakePhase { case idle, preparingInput, producing }
  private var wakePhase: WakePhase = .idle
  // Also fixes the first frame's deadline while readiness/input gates are closed.
  private var pendingContentDeadline: Double?
  /// Rate-cap boundary: selection time initially, advanced to synchronous completion.
  package private(set) var lastFrameBoundaryTime: Double?
  package private(set) var minimumRefreshRate = 30.0
  package private(set) var maximumRefreshRate = 60.0
  package var animationsActive = false { didSet { schedule() } }
  package var contentAnimationActive = false { didSet { schedule() } }
  package var inputPending = false { didSet { schedule() } }
  package var isReady = false { didSet { schedule() } }
  /// Synchronous readiness notification; the host prepares input before taking a frame.
  package var onWake: (@MainActor () -> Void)? { didSet { schedule() } }

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
    if pendingContentDeadline == nil { pendingContentDeadline = clock() }
    schedule()
  }

  package var hasContentRequest: Bool { pendingContentDeadline != nil }

  package var nextFrame: ScheduledFrame? {
    if let pendingContentDeadline {
      return ScheduledFrame(
        deadline: lastFrameBoundaryTime.map { $0 + 1 / maximumRefreshRate } ?? pendingContentDeadline,
        kind: .content, priority: .userInitiated)
    }
    guard let animationDeadline else { return nil }
    return ScheduledFrame(
      deadline: animationDeadline,
      kind: contentAnimationActive ? .content : .animation, priority: .utility)
  }

  /// Animation cadence, independent of content demand and backend readiness.
  package var animationDeadline: Double? {
    guard animationsActive || contentAnimationActive, let lastFrameBoundaryTime else { return nil }
    return lastFrameBoundaryTime + 1 / minimumRefreshRate
  }

  /// Select after input preparation and establish a provisional rate-cap boundary.
  package func takeFrame() -> FrameKind? {
    let now = clock()
    guard let nextFrame, now >= nextFrame.deadline else { return nil }
    pendingContentDeadline = nil
    if wakePhase == .preparingInput { wakePhase = .producing }
    lastFrameBoundaryTime = now
    return nextFrame.kind
  }

  package func consumeContentRequest() {
    pendingContentDeadline = nil
    schedule()
  }

  /// Advance the boundary to completion; never schedule catch-up frames from start time.
  package func recordProducedFrame() {
    lastFrameBoundaryTime = clock()
    schedule()
  }

  package func reset() {
    clearWake()
    // Keep scheduling suppressed until an in-flight wake returns, but discard its completion.
    if wakePhase == .producing { wakePhase = .preparingInput }
    pendingContentDeadline = nil
    lastFrameBoundaryTime = nil
    animationsActive = false
    contentAnimationActive = false
    inputPending = false
  }

  deinit { wakeTask?.cancel() }

  private func clearWake(cancelTask: Bool = true) {
    if cancelTask { wakeTask?.cancel() }
    wakeTask = nil
    scheduled = nil
  }

  private func schedule() {
    guard wakePhase == .idle else { return }
    let next = isReady && !inputPending && onWake != nil ? nextFrame : nil
    guard next != scheduled else { return }
    clearWake()
    scheduled = next
    guard let next else { return }
    let delay = max(0, next.deadline - clock())
    wakeTask = Task(priority: next.priority) { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      guard let self, !Task.isCancelled else { return }
      self.clearWake(cancelTask: false)
      // Hosts prepare input before taking a frame; a wake-up does not commit its kind.
      if self.isReady, !self.inputPending, let next = self.nextFrame, self.clock() >= next.deadline {
        self.wakePhase = .preparingInput
        self.onWake?()
        let produced = self.wakePhase == .producing
        self.wakePhase = .idle
        if produced { self.recordProducedFrame() }
      }
      self.schedule()
    }
  }
}
