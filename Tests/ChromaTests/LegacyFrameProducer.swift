import Foundation
import Observation
@testable import Chroma

@MainActor
final class FrameProducer {
  private var generation: UInt64 = 0
  private var subscription: FrameTrackingSubscription?
  private var registrationSubscription: FrameTrackingSubscription?
  private var registrationViewport: Size?
  private weak var interaction: Interaction?

  private let clock: @MainActor () -> Double
  private var cachedCommands: [DrawCommand] = []
  private var animationPaints: [AnimationPaint] = []
  var needsAnimationFrame: Bool { !animationPaints.isEmpty }

  init(clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    self.clock = clock
  }

  func reset() {
    cachedCommands = []
    animationPaints = []
    interaction?.resetRegistrations()
    interaction = nil
    resetTracking()
    registrationSubscription?.cancel()
    registrationSubscription = nil
    registrationViewport = nil
  }

  private func resetTracking() {
    generation &+= 1
    subscription?.cancel()
    subscription = nil
  }

  deinit {
    subscription?.cancel()
    registrationSubscription?.cancel()
  }

  func render(
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
      drawRegistrations(content, into: &drawList, viewport: viewport, context: context)
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

  func renderAnimations() -> DrawList {
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

  func refreshRegistrations(
    _ content: (any Block)?, viewport: Size, context: BlockContext, commands: [Command] = []
  ) {
    let interaction = context.interaction
    interaction.refreshingRegistrations = interaction.tree != nil
    interaction.beginFrame(input: InputState(commands: commands))
    interaction.refreshingRegistrations = true
    defer { interaction.refreshingRegistrations = false }
    var discarded = DrawList()
    drawRegistrations(content, into: &discarded, viewport: viewport, context: context)
    interaction.endFrame()
  }

  func registrationsAreValid(viewport: Size) -> Bool {
    registrationViewport == viewport && registrationSubscription?.isActive == true
  }

  private func drawRegistrations(
    _ content: (any Block)?, into list: inout DrawList, viewport: Size, context: BlockContext
  ) {
    if EngineDiagnostics.enabled { EngineDiagnostics.registrationPasses += 1 }
    registrationSubscription?.cancel()
    let subscription = FrameTrackingSubscription({})
    registrationSubscription = subscription
    registrationViewport = viewport
    withObservationTracking(options: .didSet) {
      subscription.trackCancellation()
      if let content {
        BlockEngine.draw(content, into: &list, in: Rect(origin: .zero, size: viewport), context: context)
      }
    } onChange: { [weak subscription] event in
      event.cancel()
      _ = subscription?.takeCallback()
    }
  }

}
