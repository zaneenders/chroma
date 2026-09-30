import Foundation
import Observation
import Synchronization

final class FrameTrackingSubscription: Observable, Sendable {
  private let registrar = ObservationRegistrar()
  private let callback: Mutex<(@MainActor @Sendable () -> Void)?>

  init(_ onChange: @escaping @MainActor @Sendable () -> Void) {
    callback = Mutex(onChange)
  }

  private var isCancelled: Bool {
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
  private var generation: UInt64 = 0
  private var subscription: FrameTrackingSubscription?
  private weak var interaction: Interaction?

  private let clock: @MainActor () -> Double
  private var cachedCommands: [DrawCommand] = []
  private var animationPaints: [AnimationPaint] = []
  package var needsAnimationFrame: Bool { !animationPaints.isEmpty }

  package init(clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    self.clock = clock
  }

  package func reset() {
    cachedCommands = []
    animationPaints = []
    interaction?.resetRegistrations()
    interaction = nil
    resetTracking()
  }

  private func resetTracking() {
    generation &+= 1
    subscription?.cancel()
    subscription = nil
  }

  deinit { subscription?.cancel() }

  package func render(
    content: (any Block)?,
    viewport: Size,
    input: InputState,
    context: BlockContext,
    processingInput: Bool = true,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    resetTracking()
    self.interaction = context.interaction
    let generation = generation
    let interaction = context.interaction
    interaction.viewport = Rect(origin: .zero, size: viewport)
    interaction.animationFrame = AnimationFrame(timestamp: clock())
    if interaction.tree == nil {
      let editingLeaf = interaction.editingLeaf
      let wasEditing = interaction.isTextEditing
      let caret = interaction.caretOffset
      let selection = interaction.textSelectionRange
      refreshRegistrations(content, viewport: viewport, context: context)
      if let editingLeaf, interaction.tree?.findLeaf(editingLeaf) != nil {
        interaction.beginEditing(editingLeaf, caretOffset: caret)
        interaction.textSelectionRange = selection
        if !wasEditing { interaction.stopInput() }
      }
    }
    if !input.textEvents.isEmpty || !input.commands.isEmpty || input.pointerPressed || input.pointerReleased
      || input.scrollDelta != .zero
    {
      refreshRegistrations(content, viewport: viewport, context: context, commands: input.commands)
    }
    interaction.animationPaints = []
    interaction.beginFrame(input: input, processingInput: processingInput)
    let subscription = FrameTrackingSubscription(onChange)
    self.subscription = subscription
    let enqueue = ObservationDelivery.enqueue
    let drawList = withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      var drawList = DrawList()
      if let content {
        BlockEngine.draw(
          content, into: &drawList, in: Rect(origin: .zero, size: viewport), context: context)
      }
      return drawList
    } onChange: { [weak self, weak subscription] event in
      event.cancel()
      guard let onChange = subscription?.takeCallback() else { return }
      enqueue { [weak self] in
        guard let self, self.generation == generation else { return }
        onChange()
      }
    }
    interaction.endFrame()
    var result = drawList
    interaction.paintNavigation(into: &result, theme: context.theme)
    cachedCommands = result.commands
    animationPaints = interaction.animationPaints
    interaction.animationPaints = []
    return result
  }

  package func renderAnimations() -> DrawList {
    let frame = AnimationFrame(timestamp: clock())
    interaction?.animationFrame = frame
    var commands: [DrawCommand] = []
    var cursor = 0
    for animation in animationPaints {
      commands.append(contentsOf: cachedCommands[cursor..<animation.range.lowerBound])
      var animated = DrawList()
      animation.paint(&animated, frame)
      commands.append(contentsOf: animated.commands)
      cursor = animation.range.upperBound
    }
    commands.append(contentsOf: cachedCommands[cursor...])
    return DrawList(commands: commands)
  }

  package func refreshRegistrations(
    _ content: (any Block)?, viewport: Size, context: BlockContext, commands: [Command] = []
  ) {
    let interaction = context.interaction
    let previousPass = interaction.framePass
    defer { interaction.framePass = previousPass }
    // Bootstrap input state only when there is no existing registration tree.
    interaction.framePass = interaction.tree == nil ? .painting : .registrations
    interaction.beginFrame(input: InputState(commands: commands))
    interaction.framePass = .registrations
    var discarded = DrawList()
    if let content {
      BlockEngine.draw(content, into: &discarded, in: Rect(origin: .zero, size: viewport), context: context)
    }
    interaction.endFrame()
  }

}
