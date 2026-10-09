import Testing

@testable import Chroma

@MainActor
struct ScrollMetadataTests {
  @Test(arguments: [false, true])
  func longScrollRetainsOnlyCurrentRowsAndRememberedLeaf(multipleControls: Bool) {
    let runtime = WindowRuntime()
    let context = runtime.context
    let controller = ScrollViewController()
    let content = ScrollView(data: 0..<10_000, rowHeight: 20, controller: controller) { _ in
      if multipleControls {
        HStack {
          Button("Left") {}
          VStack { Button("Right") {} }
        }
      } else {
        Color.white
      }
    }
    runtime.build = { buffer, context in buffer.emit(content, context: context) }
    func render(_ commands: [NavigationCommand] = []) {
      _ = runtime.render(
        viewport: Size(width: 200, height: 100),
        input: InputState(commands: commands.map { .navigation($0) }), onChange: {})
    }
    render()
    render([.down, .stepIn])
    if multipleControls { render([.right]) }
    let remembered = context.interaction.selectedLeafID
    render([.stepOut])
    let initial = context.interaction.scrollStates.values.first!.rows.count
    for step in 1...1_000 {
      controller.scroll(to: Float(step * 180))
      render()
    }
    let state = context.interaction.scrollStates.values.first!
    #expect(state.rows.count <= initial + (multipleControls ? 3 : 2))
    #expect(state.rows.count == (multipleControls ? 15 : 8))
    #expect(state.rowKeys.count == state.rows.count)
    render([.stepIn])
    render()
    #expect(controller.offset == 0)
    #expect(context.interaction.selectedLeafID == remembered)
    runtime.reset()
    #expect(context.interaction.scrollStates.isEmpty)
  }

  @Test func registrationOnlyScrollAlsoEvictsOldRows() {
    let context = BlockContext()
    let producer = FrameProducer()
    let controller = ScrollViewController()
    let content = ScrollView(data: 0..<10_000, rowHeight: 20, controller: controller) { _ in Color.white }
    context.interaction.viewport = Rect(x: 0, y: 0, width: 200, height: 100)
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 200, height: 100),
      context: context)
    for _ in 1...1_000 {
      context.interaction.processInput(
        InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -180)))
      context.interaction.finishInput()
      producer.refreshRegistrations(
        { buffer, context in buffer.emit(content, context: context) }, viewport: Size(width: 200, height: 100),
        context: context)
    }
    #expect(controller.offset == 180_000)
    let state = context.interaction.scrollStates.values.first!
    #expect(state.rows.count == 7)
    #expect(state.rowKeys.count == 7)
    #expect(context.interaction.registrations.scrollRows.isEmpty)
    #expect(context.interaction.building.scrollRows.isEmpty)
    producer.refreshRegistrations(
      { buffer, context in buffer.emit(EmptyBlock(), context: context) }, viewport: Size(width: 200, height: 100),
      context: context)
    #expect(context.interaction.scrollStates.isEmpty)
  }

  @MainActor private final class RegistrationHarness {
    let interaction = Interaction()
    let scrollID = WidgetID("scroll")
    let rect = Rect(x: 0, y: 0, width: 200, height: 100)

    @MainActor func register(_ leaves: [(WidgetID, Int)], count: Int = 100) {
      interaction.beginFrame(input: InputState(), processingInput: false)
      interaction.registerScrollInput(id: scrollID, rect: rect)
      interaction.updateScrollLayout(
        id: scrollID, layout: .init(width: 200, spacing: 0, rows: .uniform(count: count, height: 20, keys: nil)))
      for (leaf, key) in leaves {
        interaction.recordScrollRow(
          id: scrollID, leafID: leaf, rowKey: StructuralKey(key),
          rect: Rect(x: 0, y: Float(key * 20), width: 200, height: 20))
      }
      interaction.endFrame()
    }
  }

  @Test func rememberedAndPendingLeavesHaveIndependentBoundedLifetimes() {
    let h = RegistrationHarness()
    let remembered = WidgetID("remembered")
    let pending = WidgetID("pending")
    let visible = WidgetID("visible")
    h.register([(remembered, 0), (pending, 1), (visible, 2)])
    h.interaction.rememberedNavigation[h.scrollID] = remembered
    h.interaction.pendingFocus = .init(leaf: pending, scrollID: h.scrollID)
    h.interaction.scrollStates[h.scrollID]?.pendingReveal = h.rect
    h.register([(visible, 2)])
    #expect(Set(h.interaction.scrollStates[h.scrollID]!.rows.keys) == [remembered, pending, visible])
    #expect(h.interaction.scrollStates[h.scrollID]!.rowKeys.count == 3)

    h.interaction.rememberedNavigation[h.scrollID] = visible
    h.register([(visible, 2)])
    #expect(Set(h.interaction.scrollStates[h.scrollID]!.rows.keys) == [pending, visible])
    h.interaction.pendingFocus = nil
    h.register([(visible, 2)])
    #expect(Set(h.interaction.scrollStates[h.scrollID]!.rows.keys) == [visible])
    #expect(h.interaction.scrollStates[h.scrollID]!.rowKeys.count == 1)
  }

  @Test func realizedRowDropsRemovedControlEvenWhenRememberedOrPending() {
    let h = RegistrationHarness()
    let old = WidgetID("old")
    let replacement = WidgetID("replacement")
    h.register([(old, 0)])
    h.interaction.rememberedNavigation[h.scrollID] = old
    h.interaction.pendingFocus = .init(leaf: old, scrollID: h.scrollID)
    h.interaction.scrollStates[h.scrollID]?.pendingReveal = h.rect
    h.register([(replacement, 0)])
    #expect(Set(h.interaction.scrollStates[h.scrollID]!.rows.keys) == [replacement])
    #expect(Set(h.interaction.scrollStates[h.scrollID]!.rowKeys.keys) == [replacement])
  }

  @Test func layoutChangeReleasesOffscreenRememberedMetadata() {
    let h = RegistrationHarness()
    let old = WidgetID("old")
    let visible = WidgetID("visible")
    h.register([(old, 0)])
    h.interaction.rememberedNavigation[h.scrollID] = old
    h.register([(visible, 1)], count: 101)
    #expect(Set(h.interaction.scrollStates[h.scrollID]!.rows.keys) == [visible])
    #expect(Set(h.interaction.scrollStates[h.scrollID]!.rowKeys.keys) == [visible])
  }

  @Test func contentOnlyControlReplacementDoesNotAccumulateMetadata() {
    let runtime = WindowRuntime()
    let context = runtime.context
    let controller = ScrollViewController()
    @MainActor final class Model { var revision = 0 }
    let model = Model()
    let content = DeferredBlock {
      ScrollView(data: 0..<100, rowHeight: 20, controller: controller) { _ in
        Button("Control") {}.id(model.revision)
      }
    }
    runtime.build = { buffer, context in buffer.emit(content, context: context) }
    func render(_ commands: [NavigationCommand] = []) {
      _ = runtime.render(
        viewport: Size(width: 200, height: 100),
        input: InputState(commands: commands.map { .navigation($0) }), onChange: {})
    }
    render()
    render([.down, .stepIn, .stepOut])
    for revision in 1...100 {
      model.revision = revision
      render()
      let state = context.interaction.scrollStates.values.first!
      #expect(state.rows.count <= 7)
      #expect(state.rowKeys.count == state.rows.count)
    }
    render([.stepIn])
    #expect(context.interaction.selectedLeafID != nil)
  }
}
