import Testing

@testable import Chroma

@MainActor
struct CommandConsumptionTests {
  @Test func handledApplicationCommandDoesNotScroll() {
    let interaction = Interaction()
    let id = WidgetID("scroll")
    var handled = 0
    func frame(_ input: InputState = InputState()) {
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      let view: LayoutBuilder = { buffer, context in
        let node5 = buffer.scrollView(
          ScrollView(build: { buffer, context in
            let node3 = buffer.color(Color.white, context: context)
            return buffer.sizing(node3, y: .fixed(100), context: context)
          }), context: context.keyed(id))
        let node6 = buffer.onCommand(
          node5, .application("resize"), context: context,
          action: {
            handled += 1
            return .handled
          })
        return node6
      }
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = view(&resolvedBuffer, LayoutContext(interaction: interaction))
        resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 100, height: 20))
        resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20))
      }
      interaction.endFrame()
    }
    frame()
    frame(InputState(commands: [.application("resize")]))
    #expect(handled == 1)
    #expect(interaction.scrollState(for: id).offset.y == 0)
  }

  @Test func commandConsumptionResetsBetweenFrames() {
    let interaction = Interaction()
    let id = WidgetID("scroll")
    var consumes = true
    func frame(_ input: InputState = InputState()) {
      beginTestFrame(interaction, input: input)
      var list = DrawList()
      let view: LayoutBuilder = { buffer, context in
        let node9 = buffer.scrollView(
          ScrollView(build: { buffer, context in
            let node7 = buffer.color(Color.white, context: context)
            return buffer.sizing(node7, y: .fixed(100), context: context)
          }), context: context.keyed(id))
        let node10 = buffer.onCommand(
          node9, .application("resize"), context: context,
          action: {
            consumes ? .handled : .ignored
          })
        return node10
      }
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = view(&resolvedBuffer, LayoutContext(interaction: interaction))
        resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 100, height: 20))
        resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20))
      }
      interaction.endFrame()
    }
    frame()
    frame(InputState(commands: [.application("resize")]))
    #expect(interaction.scrollState(for: id).offset.y == 0)
    #expect(interaction.handledCommandIndices == [0])
    consumes = false
    frame(InputState(commands: [.application("resize")]))
    #expect(interaction.scrollState(for: id).offset.y == 0)
    #expect(interaction.handledCommandIndices.isEmpty)
  }
}
