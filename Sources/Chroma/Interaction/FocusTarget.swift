import Observation

@Observable
@MainActor
public final class FocusTarget {
  var pendingEditing: Bool?
  weak var interaction: Interaction?
  var boundID: WidgetID?

  public var isFocused: Bool {
    guard let interaction, let boundID else { return false }
    return interaction.selectedLeafID == boundID
  }

  public var isEditing: Bool {
    guard let interaction, let boundID else { return false }
    return interaction.isTextEditing && interaction.editingLeaf == boundID
  }

  public init() {}

  public func focus(editing: Bool = false) {
    pendingEditing = editing
    interaction?.requestRedraw()
  }
}

public struct FocusTargetBlock: LayoutPreparingBlock, CollectionDistributingBlock {
  var content: any Block
  let target: FocusTarget

  public var preservesContentIdentity: Bool { true }

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
      precondition(building.focusTargets[key] == nil, "FocusTarget must bind to exactly one control")
      building.focusTargets[key] = (target, id)
    }
  }

  func resolveFocusTargets() {
    for (key, binding) in registrations.focusTargets where building.focusTargets[key] == nil {
      binding.target.boundID = nil
      binding.target.interaction = nil
      binding.target.pendingEditing = nil
    }
    for binding in building.focusTargets.values {
      binding.target.boundID = binding.id
      if binding.target.interaction !== self { binding.target.interaction = self }
      if let editing = binding.target.pendingEditing {
        binding.target.pendingEditing = nil
        focus(binding.id, editing: editing)
        requestRedraw()
      }
    }
  }
}
