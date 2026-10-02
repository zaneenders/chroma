public struct AnimationFrame: Equatable, Sendable {
  public let timestamp: Double

  public init(timestamp: Double) {
    self.timestamp = timestamp
  }
}

@MainActor
struct AnimationPaint {
  var requiresEditing = false
  let range: Range<Int>
  let paint: @MainActor (inout DrawList, AnimationFrame) -> Void
}

extension BlockContext {
  public var animationTimestamp: Double { interaction.animationFrame.timestamp }

  func animateCaret(
    into drawList: inout DrawList,
    _ paint: @escaping @MainActor (inout DrawList, AnimationFrame) -> Void
  ) {
    let count = interaction.animationPaints.count
    animate(into: &drawList, isActive: interaction.isTextEditing, paint)
    if interaction.animationPaints.count > count {
      interaction.animationPaints[count].requiresEditing = true
    }
  }

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
