import Testing
@testable import Chroma

private struct FixedContent: PrimitiveBlock {
  var size: Size
  func sizeThatFits(_ proposal: Size) -> Size { size }
  func draw(into drawList: inout DrawList, in rect: Rect) {
    drawList.fillRect(rect, color: .white)
  }
}

@Suite(.serialized)
@MainActor
struct ScrollViewTests {
  private let viewport = Rect(x: 0, y: 0, width: 100, height: 20)
  private let scrollID = WidgetID("test-scroll")

  private func drawFrame(
    _ interaction: Interaction,
    input: InputState = InputState(),
    controller: ScrollViewController? = nil,
    sticksToBottom: Bool = false
  ) -> DrawList {
    Interaction.current = interaction
    interaction.beginFrame(input: input)
    var list = DrawList()
    let view = ScrollView(
      id: scrollID, showsIndicator: true, sticksToBottom: sticksToBottom,
      controller: controller
    ) {
      FixedContent(size: Size(width: 100, height: 100))
    }
    BlockEngine.draw(view, into: &list, in: viewport)
    interaction.endFrame()
    return list
  }

  @Test func wheelRetainsOffsetAndProducesBalancedClip() {
    let interaction = Interaction()
    _ = drawFrame(interaction)
    let list = drawFrame(
      interaction,
      input: InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -15))
    )

    #expect(interaction.scrollOffset(for: scrollID) == 15)
    #expect(list.commands.first == .pushClip(viewport))
    #expect(list.commands.last == .popClip)
  }

  @Test func controllerScrollsToBottom() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    _ = drawFrame(interaction, controller: controller)
    controller.scrollToBottom()
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollOffset(for: scrollID) == 80)
  }

  @Test func controllerScrollsOnlyEnoughToRevealRect() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    _ = drawFrame(interaction, controller: controller)

    controller.scrollToVisible(Rect(x: 0, y: 25, width: 100, height: 10))
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollOffset(for: scrollID) == 15)

    // This rectangle is already fully visible in current window coordinates.
    controller.scrollToVisible(Rect(x: 0, y: 5, width: 100, height: 10))
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollOffset(for: scrollID) == 15)

    controller.scrollToVisible(Rect(x: 0, y: -5, width: 100, height: 10))
    _ = drawFrame(interaction, controller: controller)
    #expect(interaction.scrollOffset(for: scrollID) == 10)
  }

  @Test func clippedLeafCannotBeHitOutsideViewport() {
    let interaction = Interaction()

    func frame(_ input: InputState = InputState()) {
      interaction.beginFrame(input: input)
      interaction.beginGroup(.vertical, rect: Rect(x: 0, y: 0, width: 100, height: 100))
      _ = interaction.interactiveBehavior(
        id: WidgetID("visible"), rect: Rect(x: 0, y: 0, width: 100, height: 10))
      interaction.pushClip(Rect(x: 0, y: 10, width: 100, height: 10))
      _ = interaction.interactiveBehavior(
        id: WidgetID("clipped"), rect: Rect(x: 0, y: 10, width: 100, height: 90))
      interaction.popClip()
      interaction.endGroup()
      interaction.endFrame()
    }

    frame()
    frame(InputState(pointerPosition: Point(x: 50, y: 50)))
    #expect(interaction.selection == [0, 0])
    frame(InputState(pointerPosition: Point(x: 50, y: 15)))
    #expect(interaction.selection == [0, 1])
  }
}
