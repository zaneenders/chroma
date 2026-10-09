struct ContextModifier: Block {
  enum Operation {
    case hover(HoverStyle)
    case navigationIgnored
  }

  var content: any Block
  var operation: Operation

}
