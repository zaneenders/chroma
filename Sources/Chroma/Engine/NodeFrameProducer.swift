import Foundation
import Observation

@MainActor
final class NodeFrameProducer {
  init(clock: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    self.clock = clock
  }

  private let clock: @MainActor () -> Double
  private weak var interaction: Interaction?
  private var cachedCommands: [DrawCommand] = []
  private var animationPaints: [AnimationPaint] = []
  private var scene = NodeScene()
  private var subscription: FrameTrackingSubscription?
  private var viewport: Size?
  private var metrics: FontMetrics?
  private(set) var builds = 0
  private(set) var paints = 0
  var textLayoutBuilds: Int { scene.textLayoutBuilds }
  var needsAnimationFrame: Bool {
    animationPaints.contains {
      !$0.requiresEditing
        || (interaction?.editingLeaf != nil && (interaction?.isTextEditing == true || $0.allowsReadOnly)
          && interaction?.textSelectionRange == nil)
    }
  }
  var boundaryBuilds: Int { scene.boundaryBuilds }
  var measurements: Int { scene.measurements }
  var layouts: Int { scene.layouts }
  var preparations: Int { scene.preparations }

  func reset() {
    cachedCommands = []
    animationPaints = []
    interaction?.animationPaints = []
    interaction = nil
    subscription?.cancel()
    subscription = nil
    scene.resetTracking()
    viewport = nil
    metrics = nil
  }

  func clear() {
    reset()
    scene = NodeScene()
  }

  deinit {
    subscription?.cancel()
  }

  func refresh(
    content: any Block, viewport: Size, context: BlockContext, forceEditorText: Bool = false,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) throws {
    self.interaction = context.interaction
    context.interaction.animationFrame = AnimationFrame(timestamp: clock())
    scene.onChange = onChange
    let needsBuild = subscription?.isActive != true
    let textChanged = !needsBuild && scene.refreshEditorText(force: forceEditorText)
    guard
      needsBuild || textChanged || scene.hasPendingFocus || !scene.editorTextIsValid || !scene.boundariesAreValid
        || self.viewport != viewport || metrics != context.fontMetrics
    else {
      return
    }
    if needsBuild {
      reset()
      let subscription = FrameTrackingSubscription(onChange)
      self.subscription = subscription
      try withObservationTracking(options: .didSet) {
        subscription.trackCancellation()
        try scene.update(content, context: context)
      } onChange: { [weak subscription] event in
        event.cancel()
        if let callback = subscription?.takeCallback() { ObservationDelivery.enqueue(callback) }
      }
      builds += 1
    }
    self.interaction = context.interaction
    scene.onChange = onChange
    try scene.refreshBoundaries()
    try scene.layout(in: Rect(origin: .zero, size: viewport))
    scene.prepareIfNeeded(viewport: viewport)
    self.viewport = viewport
    metrics = context.fontMetrics
  }

  func dispatch(_ input: InputState, onChange: @escaping @MainActor @Sendable () -> Void) throws {
    interaction?.animationFrame = AnimationFrame(timestamp: clock())
    scene.onChange = onChange
    if scene.refreshEditorText(force: pollsEditorText(input)), let viewport {
      try scene.layout(in: Rect(origin: .zero, size: viewport))
    }
    scene.prepareIfNeeded()
    scene.processInput(input)
    if scene.refreshEditorText(force: pollsEditorText(input)), let viewport {
      try scene.layout(in: Rect(origin: .zero, size: viewport))
    }
    try scene.refreshScroll()
    scene.prepareIfNeeded()
  }

  private func pollsEditorText(_ input: InputState) -> Bool {
    input.pointerPressed || input.pointerReleased || input.pointerDown
      || !input.commands.isEmpty || !input.textEvents.isEmpty
  }

  func paint() -> DrawList {
    interaction?.animationFrame = AnimationFrame(timestamp: clock())
    interaction?.animationPaints = []
    paints += 1
    let list = scene.paint()
    cachedCommands = list.commands
    animationPaints = interaction?.animationPaints ?? []
    interaction?.animationPaints = []
    return list
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
}
