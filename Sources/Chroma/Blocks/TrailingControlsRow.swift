public struct TrailingControlsRow<Input: Block, Controls: Block>: PrimitiveBlock {
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

  @MainActor public var expandsHorizontally: Bool { true }

  @MainActor public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
    let sizes = measuredSizes(for: proposal, context: context)
    return Size(
      width: proposal.width,
      height: max(sizes.input.height, sizes.controls.height))
  }

  @MainActor public func draw(into drawList: inout DrawList, in rect: Rect, context: RenderContext) {
    let sizes = measuredSizes(for: rect.size, context: context)
    let inputRect = Rect(
      x: rect.minX,
      y: rect.maxY - sizes.input.height,
      width: sizes.input.width,
      height: sizes.input.height)
    let controlsRect = Rect(
      x: rect.maxX - sizes.controls.width,
      y: rect.maxY - sizes.controls.height,
      width: sizes.controls.width,
      height: sizes.controls.height)

    context.withFocusGroup(in: rect) {
      BlockEngine.draw(input, into: &drawList, in: inputRect, context: context)
      BlockEngine.draw(controls, into: &drawList, in: controlsRect, context: context)
    }
  }

  @MainActor private func measuredSizes(
    for proposal: Size, context: RenderContext
  ) -> (input: Size, controls: Size) {
    let controlsSize = BlockEngine.measure(controls, proposal: proposal, context: context)
    let inputWidth = max(0, proposal.width - controlsSize.width - spacing)
    let inputSize = BlockEngine.measure(
      input,
      proposal: Size(width: inputWidth, height: proposal.height),
      context: context)
    return (
      input: Size(width: inputWidth, height: inputSize.height),
      controls: controlsSize
    )
  }
}

