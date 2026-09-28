@MainActor
package final class WindowRuntime {
  package init() {}

  package let interaction = Interaction()
  private let producer = FrameProducer()

  package var content: (any Block)? {
    didSet { reset() }
  }
  package var keyBindings = KeyBindings()
  package var frameObserver: FrameObserver?
  package var needsAnimationFrame: Bool { producer.needsAnimationFrame }
  package var context: RenderContext { RenderContext(interaction: interaction) }

  package func resolve(_ input: KeyboardInput) -> ResolvedKeyboardInput? {
    interaction.resolve(input, appBindings: keyBindings)
  }

  package func reset() {
    producer.reset()
  }

  package func render(
    viewport: Size,
    input: InputState,
    onChange: @escaping @MainActor @Sendable () -> Void
  ) -> DrawList {
    producer.render(
      content: content, viewport: viewport, input: input, context: context, onChange: onChange)
  }

  package func observe(_ list: DrawList, viewport: Size, rasterScale: Point? = nil) {
    frameObserver?(FrameObservation(drawList: list, viewport: viewport, rasterScale: rasterScale))
  }
}
