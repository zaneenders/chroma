import Testing

@testable import Chroma

@MainActor
struct ScrollNavigationTests {
  @MainActor private final class Harness {
    let context = RenderContext()
    let producer = FrameProducer()
    func render(_ content: any Block, _ commands: [NavigationCommand] = []) {
      _ = producer.render(
        content: content, viewport: Size(width: 200, height: 100),
        input: InputState(commands: commands.map { .navigation($0) }), context: context, onChange: {})
    }
  }

  @Test func lazyListIsOneBoundaryAndRestoresVirtualizedRow() {
    let h = Harness()
    let controller = ScrollViewController()
    let rows = (0..<40).map { _ in FocusTarget() }
    let content = LazyVStack(data: rows.indices, rowHeight: 20, controller: controller) { index in
      Button("Row \(index)") {}.focusTarget(rows[index])
    }
    h.render(content)
    #expect(!rows.contains { $0.isFocused })
    h.render(content, [.down, .stepIn])
    #expect(rows[0].isFocused)
    for _ in 0..<12 { h.render(content, [.down]) }
    #expect(rows[12].isFocused)
    h.render(content, [.stepOut])
    #expect(!rows.contains { $0.isFocused })
    #expect(h.context.interaction.navigationPath.count == 1)
    controller.scrollToTop()
    h.render(content)
    #expect(controller.offset == 0)
    h.render(content, [.stepIn])
    h.render(content)
    #expect(rows[12].isFocused)
    #expect(controller.offset > 0)
  }

  @Test func removedRememberedRowFallsBackWithoutActivatingAnother() {
    let h = Harness()
    let controller = ScrollViewController()
    @MainActor final class Rows { var ids = [0, 1, 2] }
    let rows = Rows()
    var calls = 0
    let content = DeferredBlock {
      LazyVStack(data: rows.ids, rowHeight: 20, controller: controller) { index in
        Button("Row \(index)") { calls += 1 }
      }
    }
    h.render(content)
    h.render(content, [.down, .stepIn, .down, .stepOut])
    rows.ids.remove(at: 1)
    h.render(content)
    h.render(content, [.stepIn])
    #expect(h.context.interaction.selectedLeafID != nil)
    #expect(calls == 0)
  }

  @Test func scrollControllerRestoresBothAxesAndResetsForNewIdentity() {
    let h = Harness()
    let controller = ScrollViewController()
    func content(_ id: Int) -> some Block {
      ScrollView(controller: controller) { Color.white.sizing(x: .fixed(500), y: .fixed(500)) }.id(id)
    }
    h.render(content(1))
    _ = h.producer.render(
      content: content(1), viewport: Size(width: 200, height: 100),
      input: InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: -25, y: -60)),
      context: h.context, onChange: {})
    #expect(controller.offset == 60)
    #expect(controller.horizontalOffset == 25)
    h.render(EmptyBlock())
    h.render(content(1))
    #expect(controller.offset == 60)
    #expect(controller.horizontalOffset == 25)
    h.render(content(2))
    #expect(controller.offset == 0)
    #expect(controller.horizontalOffset == 0)
  }
}
