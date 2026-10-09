public struct TrailingControlsRow<Input: Block, Controls: Block>: Block {
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

  @MainActor public func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
    let input = buffer.emit(input, context: context.childScope(0))
    let controls = buffer.emit(controls, context: context.childScope(1))
    return buffer.node(.trailing(input, controls, spacing), context: context)
  }
}
