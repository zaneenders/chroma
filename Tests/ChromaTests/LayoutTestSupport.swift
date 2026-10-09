import Chroma

@MainActor
func measureBlock(_ block: any Block, proposal: Size, context: BlockContext) -> Size {
  var buffer = LayoutBuffer()
  let node = buffer.emit(block, context: context)
  return buffer.sizeThatFits(node, proposal)
}

@MainActor
func blockExpandsHorizontally(_ block: any Block) -> Bool {
  var buffer = LayoutBuffer()
  let node = buffer.emit(block, context: BlockContext())
  return buffer.expandsHorizontally(node)
}

@MainActor
func blockExpandsVertically(_ block: any Block) -> Bool {
  var buffer = LayoutBuffer()
  let node = buffer.emit(block, context: BlockContext())
  return buffer.expandsVertically(node)
}
