@testable import Chroma

@MainActor
func measureLayout(_ build: LayoutBuilder, proposal: Size, context: LayoutContext) -> Size {
  var buffer = LayoutBuffer()
  let node = build(&buffer, context)
  return buffer.sizeThatFits(node, proposal)
}

@MainActor
func layoutExpandsHorizontally(_ build: LayoutBuilder) -> Bool {
  var buffer = LayoutBuffer()
  let node = build(&buffer, LayoutContext())
  return buffer.expandsHorizontally(node)
}

@MainActor
func layoutExpandsVertically(_ build: LayoutBuilder) -> Bool {
  var buffer = LayoutBuffer()
  let node = build(&buffer, LayoutContext())
  return buffer.expandsVertically(node)
}

/// Low-level interaction tests dispatch an event explicitly before registering its frame.
@MainActor
func beginTestFrame(_ interaction: Interaction, input: InputState) {
  interaction.processInput(input, notifyingObservers: input != InputState())
  interaction.beginFrame(input: input)
}
