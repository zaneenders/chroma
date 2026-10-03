struct ContextModifier: LayoutPreparingBlock, CollectionDistributingBlock {
  enum Operation {
    case hover(HoverStyle)
    case navigationIgnored
  }

  var content: any Block
  var operation: Operation

  var preservesContentIdentity: Bool { true }

}
