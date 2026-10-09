import ChromaTesting
import Observation
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct LazyLayoutCacheTests {
  @Observable final class Model {
    var height: Float = 20
  }

  final class Capture {
    var measurements = 0
    var drawnHeight: Float = 0
  }

  struct Row: Block {

    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        expandsHorizontally: false, expandsVertically: false,
        measure: { sizeThatFits($0, context: context) },
        register: { register(in: $0, context: context) },
        paint: { paint(into: &$0, in: $1, context: context) })
    }

    @MainActor func register(in rect: Rect, context: BlockContext) {}

    let model: Model
    let capture: Capture

    var focusRule: FocusRule { .standard }

    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      capture.measurements += 1
      return Size(width: proposal.width, height: model.height)
    }

    @MainActor func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      capture.drawnHeight = rect.size.height
      list.fillRect(rect, color: .white)
    }
  }

  @Test func lazyMeasurementsInvalidateAndResubscribe() async {
    let model = Model()
    let capture = Capture()
    let controller = ScrollViewController()
    let renderer = HeadlessHost()
    renderer.setContent(
      ScrollView(
        controller: controller,
        rows: [.init(id: WidgetID("row"), content: Row(model: model, capture: capture))]
      ).id(WidgetID("stack")))
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    renderer.render()
    #expect(capture.measurements == 1)
    for height: Float in [50, 80] {
      redraws = 0
      model.height = height
      await drainObservationChanges()
      #expect(redraws > 0)
      renderer.render()
      #expect(capture.drawnHeight == height)
    }
    #expect(capture.measurements == 3)
    renderer.render()
    #expect(capture.measurements == 3)
    renderer.close()
  }

  @Test func lazyMeasurementsInvalidateBeforeImmediateRender() async {
    let model = Model()
    let capture = Capture()
    let controller = ScrollViewController()
    let renderer = HeadlessHost()
    defer { renderer.close() }
    renderer.setContent(
      ScrollView(
        controller: controller,
        rows: [.init(id: WidgetID("row"), content: Row(model: model, capture: capture))]
      ).id(WidgetID("stack")))
    renderer.render()
    for height: Float in [50, 80, 30] {
      model.height = height
      renderer.render()
      #expect(capture.drawnHeight == height)
    }
    #expect(capture.measurements == 4)
    await drainObservationChanges()
    renderer.render()
    #expect(capture.measurements == 4)
  }

  @Test func lazyMeasurementsReflectChangesFromInputHandlersInSameFrame() {
    let model = Model()
    let capture = Capture()
    let controller = ScrollViewController()
    let renderer = HeadlessHost()
    defer { renderer.close() }
    renderer.setContent(
      ScrollView(
        controller: controller,
        rows: [.init(id: WidgetID("row"), content: Row(model: model, capture: capture))]
      ).id(WidgetID("stack")).onCommand(.application("resize")) {
        model.height = 80
        return .handled
      })
    renderer.render()
    renderer.render(input: InputState(commands: [.application("resize")]))
    #expect(capture.drawnHeight == 80)
    #expect(capture.measurements == 2)
  }

  @Test func changedRowHeightInvalidatesCache() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let id = WidgetID("scroll")
    func frame(height: Float) {
      interaction.beginFrame(input: InputState())
      var list = DrawList()
      let stack = ScrollView(
        controller: controller,
        rows: [
          .init(id: WidgetID("stable-row"), content: Color.white.sizing(y: .fixed(height)))
        ]
      ).id(id)
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.emit(stack, context: BlockContext(interaction: interaction))
        resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 100, height: 20))
        resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20))
      }
      interaction.endFrame()
    }
    frame(height: 40)
    #expect(interaction.scrollState(for: id).limit.y == 20)
    frame(height: 100)
    #expect(interaction.scrollState(for: id).limit.y == 80)
  }

  @Test func retainedRowContentMutationInvalidatesCache() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let id = WidgetID("scroll")
    var row = ScrollView.Row(
      id: WidgetID("row"), content: Color.white.sizing(y: .fixed(40)))
    func frame() {
      interaction.beginFrame(input: InputState())
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.emit(
          ScrollView(controller: controller, rows: [row]).id(id), context: BlockContext(interaction: interaction))
        resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 100, height: 20))
        resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20))
      }
      interaction.endFrame()
    }
    frame()
    row.content = Color.white.sizing(y: .fixed(100))
    frame()
    #expect(interaction.scrollState(for: id).limit.y == 80)
  }

  @Test func retainedRowUsesCurrentTextScaleAndFontMetrics() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let id = WidgetID("scroll")
    let rows = [ScrollView.Row(id: WidgetID("row"), content: Text("row"))]
    func frame(scale: Float) {
      interaction.beginFrame(input: InputState())
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.emit(
          ScrollView(controller: controller, rows: rows).id(id),
          context: BlockContext(interaction: interaction, textScale: scale))
        resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 100, height: 20))
        resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20))
      }
      interaction.endFrame()
    }
    frame(scale: 1)
    #expect(interaction.scrollState(for: id).limit.y == 8)
    frame(scale: 2)
    #expect(interaction.scrollState(for: id).limit.y == 36)
    interaction.fontMetrics.glyphHeight = 40
    frame(scale: 2)
    #expect(interaction.scrollState(for: id).limit.y == 60)
  }
}
