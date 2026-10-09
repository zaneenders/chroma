import Foundation
import Observation
import Synchronization

final class FrameTrackingSubscription: Observable, Sendable {
  private let metricsLifetime: PipelineMetricLifetime?
  private let registrar = ObservationRegistrar()
  private let callback: Mutex<(@MainActor @Sendable () -> Void)?>

  init(_ onChange: @escaping @MainActor @Sendable () -> Void, metricsLifetime: PipelineMetricLifetime? = nil) {
    self.metricsLifetime = metricsLifetime
    callback = Mutex(onChange)
  }

  var isCancelled: Bool {
    callback.withLock { $0 == nil }
  }

  func trackCancellation() {
    registrar.access(self, keyPath: \.isCancelled)
  }

  func cancel() {
    callback.withLock { $0 = nil }
    registrar.withMutation(of: self, keyPath: \.isCancelled) {}
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
  private let clock: @MainActor () -> Double

  package init(clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    self.clock = clock
  }

  private var generation: UInt64 = 0
  private var layout = LayoutBuffer()
  private var drawBuffer = DrawList()
  private var subscription: FrameTrackingSubscription?
  private weak var interaction: Interaction?

  package func reset() {
    layout.reset(releasingCapacity: true)
    drawBuffer.removeAll(keepingCapacity: false)
    interaction?.resetRegistrations()
    interaction = nil
    resetTracking()
  }

  private func resetTracking() {
    generation += 1
    subscription?.cancel()
    subscription = nil
  }

  isolated deinit {
    subscription?.cancel()
  }

  /// Input refresh and presentation share this commit path and this buffer owner.
  private func commit(
    _ build: LayoutBuilder?, viewport: Size, context: BlockContext,
    input: InputState, refreshing: Bool, drawing: Bool
  ) {
    let interaction = context.interaction
    self.interaction = interaction
    interaction.animationTime = clock()
    interaction.refreshingRegistrations = refreshing
    interaction.beginFrame(input: input)
    defer { interaction.refreshingRegistrations = false }
    layout.reset()
    defer { layout.reset() }
    let root: LayoutNode?
    if let build { root = build(&layout, context) } else { root = nil }
    let rect = Rect(origin: .zero, size: viewport)
    if let root { layout.register(root, in: rect) }
    interaction.endFrame()
    if drawing, let root { layout.paint(root, into: &drawBuffer, in: rect) }
  }

  package func render(
    build: LayoutBuilder?, viewport: Size, input: InputState, context: BlockContext,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    resetTracking()
    let generation = generation
    let interaction = context.interaction
    interaction.viewport = Rect(origin: .zero, size: viewport)
    let subscription = FrameTrackingSubscription(
      onChange, metricsLifetime: PipelineMetrics.trackObservationLifetime())
    self.subscription = subscription
    let enqueue = ObservationDelivery.enqueue
    withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      drawBuffer.removeAll()
      commit(
        build, viewport: viewport, context: context, input: input,
        refreshing: false, drawing: true)
    } onChange: { [weak self, weak subscription] event in
      event.cancel()
      guard let onChange = subscription?.takeCallback() else { return }
      enqueue { [weak self] in
        guard let self, self.generation == generation else { return }
        onChange()
      }
    }
    let commands = drawBuffer.commands.count
    interaction.paintNavigation(into: &drawBuffer, theme: context.theme)
    PipelineMetrics.record(.drawingCommands, count: drawBuffer.commands.count - commands)
    return drawBuffer
  }

  package func refreshRegistrations(
    _ build: LayoutBuilder?, viewport: Size, context: BlockContext, commands: [Command] = [],
    keyboardNavigationOverscan: Bool = false
  ) {
    var context = context
    context.keyboardNavigationOverscan = keyboardNavigationOverscan
    commit(
      build, viewport: viewport, context: context, input: InputState(commands: commands),
      refreshing: true, drawing: false)
  }
}
