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
      let view = ScrollView {
        Color.white.sizing(y: .fixed(100))
      }.id(id).onCommand(.application("resize")) {
        handled += 1
        return .handled
      }
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.emit(view, context: BlockContext(interaction: interaction))
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
      let view = ScrollView {
        Color.white.sizing(y: .fixed(100))
      }.id(id).onCommand(.application("resize")) {
        consumes ? .handled : .ignored
      }
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.emit(view, context: BlockContext(interaction: interaction))
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
