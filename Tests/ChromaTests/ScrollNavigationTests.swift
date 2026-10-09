import Testing

@testable import Chroma

@MainActor
struct ScrollNavigationTests {
  @MainActor private final class Harness {
    let context = BlockContext()
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
    let content = ScrollView(data: rows.indices, rowHeight: 20, controller: controller) { index in
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

  @Test(arguments: [false, true])
  func logicalRowSelectionSurvivesVirtualizationAndDownRevealsSuccessor(explicitRevision: Bool) {
    let h = Harness()
    let controller = ScrollViewController()
    let selection = ScrollSelection<Int>()
    let targets = (0..<100).map { _ in FocusTarget() }
    struct Item: Identifiable { let id: Int }
    let content = ScrollView(
      data: (0..<100).map { Item(id: $0) }, rowHeight: 20, controller: controller, selection: selection,
      identityRevision: explicitRevision ? .init(source: "rows", revision: 0) : nil
    ) { index in
      Button("Row \(index.id)") {}.focusTarget(targets[index.id])
    }
    h.render(content)
    h.render(content, [.down, .stepIn, .down])
    #expect(selection.selectedID == 1)
    #expect(targets[1].isFocused)

    controller.scroll(to: 1200)
    h.render(content)
    #expect(selection.selectedID == 1)
    #expect(!targets[1].isFocused)
    h.render(content, [.down])
    #expect(selection.selectedID == 2)
    h.render(content)
    #expect(targets[2].isFocused)
    #expect(controller.offset < 1200)
  }

  @Test(arguments: [false, true])
  func retainedSelectionCallbacksKeepTheirIdentitySnapshot(explicitRevision: Bool) {
    let h = Harness()
    let controller = ScrollViewController()
    let selection = ScrollSelection<Int>()
    struct Item: Identifiable { let id: Int }
    let original = ScrollView(
      data: [Item(id: 0), Item(id: 1), Item(id: 2)], rowHeight: 20,
      controller: controller, selection: selection,
      identityRevision: explicitRevision ? .init(source: "rows", revision: 0) : nil
    ) { Text("Row \($0.id)") }
    h.render(original)
    h.render(original, [.down, .stepIn, .down])
    #expect(selection.selectedID == 1)

    let replacement = ScrollView(
      data: [Item(id: 0), Item(id: 1), Item(id: 3)], rowHeight: 20,
      controller: controller, selection: selection,
      identityRevision: explicitRevision ? .init(source: "rows", revision: 1) : nil
    ) { Text("Row \($0.id)") }
    h.render(original, [.down])
    #expect(selection.selectedID == 2)
    h.render(replacement)
    selection.selectedID = 1
    h.render(replacement, [.down])
    #expect(selection.selectedID == 3)
  }

  @Test func logicalSelectionHasExplicitMissingItemPolicy() {
    let selection = ScrollSelection(2)
    #expect(selection.move(in: [1, 3], by: 1) == nil)
    selection.selectedID = 2
    #expect(selection.move(in: [1, 3], by: 1, ifMissing: .first) == 1)
  }

  @Test func removedRememberedRowFallsBackWithoutActivatingAnother() {
    let h = Harness()
    let controller = ScrollViewController()
    @MainActor final class Rows { var ids = [0, 1, 2] }
    let rows = Rows()
    var calls = 0
    let content = DeferredBlock {
      ScrollView(data: rows.ids, rowHeight: 20, controller: controller) { index in
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

  @Test func pendingRowRevealSurvivesLayoutWidthChange() {
    let h = Harness()
    let controller = ScrollViewController()
    let content = ScrollView(data: 0..<20, rowHeight: 20, controller: controller) { index in
      Button("Row \(index)") {}
    }
    h.render(content)
    h.render(content, [.down, .stepIn])
    let interaction = h.context.interaction
    guard let scrollID = interaction.scrollStates.first(where: { $0.value.layout != nil })?.key else {
      Issue.record("Missing scroll layout")
      return
    }
    interaction.scrollStates[scrollID]?.pendingReveal = Rect(x: 0, y: 300, width: 200, height: 20)
    let expectedFocus = Interaction.PendingFocus(leaf: WidgetID("row-15"), scrollID: scrollID)
    interaction.pendingFocus = expectedFocus
    _ = h.producer.render(
      content: content, viewport: Size(width: 150, height: 100), input: InputState(),
      context: h.context, onChange: {})
    #expect(controller.offset > 0)
    #expect(interaction.pendingFocus == expectedFocus)
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
