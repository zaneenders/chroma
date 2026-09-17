import Observation

@Observable
@MainActor
public final class FocusTarget {
  var pendingEditing: Bool?
  @ObservationIgnored weak var interaction: Interaction?

  public init() {}

  public func focus(editing: Bool = false) {
    pendingEditing = editing
    interaction?.requestRedraw()
  }
}

public struct FocusTargetBlock: PrimitiveBlock, IdentityTransparentBlock {
  var content: any Block
  let target: FocusTarget

  @MainActor public var expandsHorizontally: Bool { BlockEngine.expandsHorizontally(content) }
  @MainActor public var expandsVertically: Bool { BlockEngine.expandsVertically(content) }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    BlockEngine.measure(content, proposal: proposal, context: context)
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    _ = target.pendingEditing
    var context = context
    context.focusTargets.append(target)
    BlockEngine.draw(content, into: &drawList, in: rect, context: context)
  }
}

extension Block {
  public func focusTarget(_ target: FocusTarget) -> FocusTargetBlock {
    FocusTargetBlock(content: self, target: target)
  }
}

extension Interaction {
  func registerFocusTargets(_ targets: [FocusTarget], id: WidgetID) {
    for target in targets {
      precondition(
        target.interaction == nil || target.interaction === self,
        "FocusTarget cannot be bound to multiple interaction instances")
      let key = ObjectIdentifier(target)
      precondition(buildingFocusTargets[key] == nil, "FocusTarget must bind to exactly one control")
      buildingFocusTargets[key] = (target, id)
    }
  }

  func resolveFocusTargets() {
    for (key, binding) in focusTargets where buildingFocusTargets[key] == nil {
      binding.target.interaction = nil
      binding.target.pendingEditing = nil
    }
    focusTargets = buildingFocusTargets
    for binding in focusTargets.values {
      binding.target.interaction = self
      if let editing = binding.target.pendingEditing {
        binding.target.pendingEditing = nil
        focus(binding.id, editing: editing)
        requestRedraw()
      }
    }
  }
}
