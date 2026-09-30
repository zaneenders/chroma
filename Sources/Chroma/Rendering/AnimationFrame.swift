public struct AnimationFrame: Equatable, Sendable {
  public let timestamp: Double

  public init(timestamp: Double) {
    self.timestamp = timestamp
  }
}

@MainActor
struct AnimationPaint {
  let range: Range<Int>
  let paint: @MainActor (inout DrawList, AnimationFrame) -> Void
}

extension BlockContext {
  public var animationTimestamp: Double { interaction.animationFrame.timestamp }

  /// Paint time-dependent commands without rebuilding content or layout on animation ticks.
  /// Capture layout and state here; the closure should only paint, not mutate state or register interaction.
  /// Animation paint must not nest `animate` calls.
  /// Chroma owns the cadence. Inactive paint runs once and does not keep the host awake.
  public func animate(
    into drawList: inout DrawList,
    isActive: Bool = true,
    _ paint: @escaping @MainActor (inout DrawList, AnimationFrame) -> Void
  ) {
    let start = drawList.commands.count
    let paintCount = interaction.animationPaints.count
    paint(&drawList, interaction.animationFrame)
    precondition(interaction.animationPaints.count == paintCount, "Animation paint cannot be nested")
    if isActive, !interaction.refreshingRegistrations {
      interaction.animationPaints.append(AnimationPaint(range: start..<drawList.commands.count, paint: paint))
    }
  }
}
