import Testing

@testable import Chroma

@MainActor
struct LayoutCacheAndCommandRegressionTests {
  @Test func changedRowHeightInvalidatesCache() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let id = WidgetID("scroll")
    func frame(height: Float) {
      interaction.beginFrame(input: InputState())
      var list = DrawList()
      let stack = LazyVStack(
        id: id, controller: controller,
        rows: [
          .init(id: WidgetID("stable-row"), content: Color.white.sizing(y: .fixed(height)))
        ])
      BlockEngine.draw(
        stack, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20),
        context: RenderContext(interaction: interaction))
      interaction.endFrame()
    }
    frame(height: 40)
    #expect(interaction.scrollLimit(for: id) == 20)
    frame(height: 100)
    #expect(interaction.scrollLimit(for: id) == 80)
  }

  @Test func handledPageDownDoesNotScroll() {
    let interaction = Interaction()
    let id = WidgetID("scroll")
    var handled = 0
    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      var list = DrawList()
      let view = ScrollView(id: id) {
        Color.white.sizing(y: .fixed(100))
      }.onCommand(.navigation(.pageDown)) {
        handled += 1
        return .handled
      }
      BlockEngine.draw(
        view, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20),
        context: RenderContext(interaction: interaction))
      interaction.endFrame()
    }
    frame()
    frame(InputState(commands: [.navigation(.pageDown)]))
    #expect(handled == 1)
    #expect(interaction.scrollOffset(for: id) == 0)
  }

  @Test func retainedRowContentMutationInvalidatesCache() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let id = WidgetID("scroll")
    var row = LazyVStack.Row(
      id: WidgetID("row"), content: Color.white.sizing(y: .fixed(40)))
    func frame() {
      interaction.beginFrame(input: InputState())
      var list = DrawList()
      BlockEngine.draw(
        LazyVStack(id: id, controller: controller, rows: [row]),
        into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20),
        context: RenderContext(interaction: interaction))
      interaction.endFrame()
    }
    frame()
    row.content = Color.white.sizing(y: .fixed(100))
    frame()
    #expect(interaction.scrollLimit(for: id) == 80)
  }

  @Test func retainedRowUsesCurrentTextScaleAndFontMetrics() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let id = WidgetID("scroll")
    let rows = [LazyVStack.Row(id: WidgetID("row"), content: Text("row"))]
    func frame(scale: Float) {
      interaction.beginFrame(input: InputState())
      var list = DrawList()
      BlockEngine.draw(
        LazyVStack(id: id, controller: controller, rows: rows),
        into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20),
        context: RenderContext(interaction: interaction, textScale: scale))
      interaction.endFrame()
    }
    frame(scale: 1)
    #expect(interaction.scrollLimit(for: id) == 8)
    frame(scale: 2)
    #expect(interaction.scrollLimit(for: id) == 36)
    interaction.fontMetrics.glyphHeight = 40
    frame(scale: 2)
    #expect(interaction.scrollLimit(for: id) == 60)
  }

  @Test func unhandledPageDownStillScrollsAndConsumptionResets() {
    let interaction = Interaction()
    let id = WidgetID("scroll")
    var consumes = true
    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      var list = DrawList()
      let view = ScrollView(id: id) {
        Color.white.sizing(y: .fixed(100))
      }.onCommand(.navigation(.pageDown)) {
        consumes ? .handled : .ignored
      }
      BlockEngine.draw(
        view, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20),
        context: RenderContext(interaction: interaction))
      interaction.endFrame()
    }
    frame()
    frame(InputState(commands: [.navigation(.pageDown)]))
    #expect(interaction.scrollOffset(for: id) == 0)
    consumes = false
    frame(InputState(commands: [.navigation(.pageDown)]))
    #expect(interaction.scrollOffset(for: id) == 20)
  }

}
