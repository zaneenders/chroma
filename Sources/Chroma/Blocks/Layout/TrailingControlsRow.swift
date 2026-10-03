public struct TrailingControlsRow<Input: Block, Controls: Block>: LayoutPreparingBlock {
  let spacing: Float
  let input: Input
  let controls: Controls

  public init(
    spacing: Float,
    @BlockBuilder input: () -> Input,
    @BlockBuilder controls: () -> Controls
  ) {
    self.spacing = spacing
    self.input = input()
    self.controls = controls()
  }

  @MainActor private func measuredSizes(
    for proposal: Size, context: BlockContext
  ) -> (input: Size, controls: Size) {
    let controlsSize = BlockEngine.measure(controls, proposal: proposal, context: context.childScope(1))
    let inputWidth = max(0, proposal.width - controlsSize.width - spacing)
    let inputSize = BlockEngine.measure(
      input,
      proposal: Size(width: inputWidth, height: proposal.height),
      context: context.childScope(0))
    return (
      input: Size(width: inputWidth, height: inputSize.height),
      controls: controlsSize
    )
  }
}
