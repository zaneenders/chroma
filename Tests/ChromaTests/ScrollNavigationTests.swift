import Testing

@testable import Chroma

@MainActor
struct ScrollNavigationTests {
  @MainActor private final class Harness {
    let runtime = WindowRuntime()
    var context: LayoutContext { runtime.context }
    private var content: LayoutBuilder?
    init() {
      runtime.build = { [weak self] buffer, context in
        self?.content?(&buffer, context) ?? buffer.empty(context: context)
      }
    }
    func render(_ build: @escaping LayoutBuilder, _ commands: [NavigationCommand] = []) {
      content = build
      _ = runtime.render(
        viewport: Size(width: 200, height: 100),
        input: InputState(commands: commands.map { .navigation($0) }), onChange: {})
    }
  }

  @Test func lazyListIsOneBoundaryAndRestoresVirtualizedRow() {
    let h = Harness()
    let controller = ScrollViewController()
    let rows = (0..<40).map { _ in FocusTarget() }
    let contentScroll = ScrollView(
      data: rows.indices, rowHeight: 20, controller: controller,
      build: { buffer, context, index in
        return buffer.focus(rows[index], context: context) { buffer, context in
          buffer.button(Button("Row \(index)") {}, context: context)
        }
      })
    let content: LayoutBuilder = { buffer, context in buffer.scrollView(contentScroll, context: context) }
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

  @Test func logicalRowSelectionSurvivesVirtualizationAndDownRevealsSuccessor() {
    let h = Harness()
    let controller = ScrollViewController()
    let selection = ScrollSelection<Int>()
    let targets = (0..<100).map { _ in FocusTarget() }
    struct Item: Identifiable { let id: Int }
    let contentScroll = ScrollView(
      data: (0..<100).map { Item(id: $0) }, rowHeight: 20, controller: controller, selection: selection,
      build: { buffer, context, index in
        return buffer.focus(targets[index.id], context: context) { buffer, context in
          buffer.button(Button("Row \(index.id)") {}, context: context)
        }
      })
    let content: LayoutBuilder = { buffer, context in buffer.scrollView(contentScroll, context: context) }
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

  @Test func retainedSelectionCallbacksKeepTheirIdentitySnapshot() {
    let h = Harness()
    let controller = ScrollViewController()
    let selection = ScrollSelection<Int>()
    struct Item: Identifiable { let id: Int }
    let originalScroll = ScrollView(
      data: [Item(id: 0), Item(id: 1), Item(id: 2)], rowHeight: 20,
      controller: controller, selection: selection,
      build: { buffer, context, element in
        return buffer.text(Text("Row \(element.id)"), context: context)
      })
    let original: LayoutBuilder = { buffer, context in buffer.scrollView(originalScroll, context: context) }
    h.render(original)
    h.render(original, [.down, .stepIn, .down])
    #expect(selection.selectedID == 1)

    let replacementScroll = ScrollView(
      data: [Item(id: 0), Item(id: 1), Item(id: 3)], rowHeight: 20,
      controller: controller, selection: selection,
      build: { buffer, context, element in
        return buffer.text(Text("Row \(element.id)"), context: context)
      })
    let replacement: LayoutBuilder = { buffer, context in buffer.scrollView(replacementScroll, context: context) }
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
    let content: LayoutBuilder = { buffer, context in
      buffer.scrollView(
        ScrollView(
          data: rows.ids, rowHeight: 20, controller: controller,
          build: { buffer, context, index in
            return buffer.button(Button("Row \(index)") { calls += 1 }, context: context)
          }), context: context)
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
    let contentScroll = ScrollView(
      data: 0..<20, rowHeight: 20, controller: controller,
      build: { buffer, context, index in
        return buffer.button(Button("Row \(index)") {}, context: context)
      })
    let content: LayoutBuilder = { buffer, context in buffer.scrollView(contentScroll, context: context) }
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
    _ = h.runtime.render(
      viewport: Size(width: 150, height: 100),
      input: InputState(),
      onChange: {})
    #expect(controller.offset > 0)
    #expect(interaction.pendingFocus == expectedFocus)
  }

  @Test func scrollControllerRestoresBothAxesAndResetsForNewIdentity() {
    let h = Harness()
    let controller = ScrollViewController()
    func content(_ id: Int) -> LayoutBuilder {
      { buffer, context in
        buffer.scrollView(
          ScrollView(
            controller: controller,
            build: { buffer, context in
              let child = buffer.sizing(
                buffer.color(.white, context: context.childScope(0)), x: .fixed(500), y: .fixed(500),
                context: context.childScope(0))
              return buffer.stack([child], axis: .vertical, context: context)
            }), context: context.keyed(id))
      }
    }
    h.render(content(1))
    _ = h.runtime.render(
      viewport: Size(width: 200, height: 100),
      input: InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: -25, y: -60)),
      onChange: {})
    #expect(controller.offset == 60)
    #expect(controller.horizontalOffset == 25)
    h.render({ buffer, context in buffer.empty(context: context) })
    h.render(content(1))
    #expect(controller.offset == 60)
    #expect(controller.horizontalOffset == 25)
    h.render(content(2))
    #expect(controller.offset == 0)
    #expect(controller.horizontalOffset == 0)
  }
}
