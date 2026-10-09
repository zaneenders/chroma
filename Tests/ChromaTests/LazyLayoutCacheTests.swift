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

  static func row(
    model: Model, capture: Capture, into buffer: inout LayoutBuffer, context: LayoutContext
  ) -> LayoutNode {
    buffer.customLeaf(
      context: context, focusRule: .standard,
      measure: { proposal in
        capture.measurements += 1
        return Size(width: proposal.width, height: model.height)
      }, register: { _ in },
      paint: { list, rect in
        capture.drawnHeight = rect.size.height
        list.fillRect(rect, color: .white)
      })
  }

  @Test func lazyMeasurementsInvalidateAndResubscribe() async {
    let model = Model()
    let capture = Capture()
    let controller = ScrollViewController()
    let renderer = HeadlessHost()
    let scroll = ScrollView(
      controller: controller,
      rows: [
        .init(
          id: WidgetID("row"),
          build: { buffer, context in Self.row(model: model, capture: capture, into: &buffer, context: context) })
      ]
    )
    renderer.build = { buffer, context in buffer.scrollView(scroll, context: context.keyed(WidgetID("stack"))) }
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
    let scroll = ScrollView(
      controller: controller,
      rows: [
        .init(
          id: WidgetID("row"),
          build: { buffer, context in Self.row(model: model, capture: capture, into: &buffer, context: context) })
      ]
    )
    renderer.build = { buffer, context in buffer.scrollView(scroll, context: context.keyed(WidgetID("stack"))) }
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
    let scroll = ScrollView(
      controller: controller,
      rows: [
        .init(
          id: WidgetID("row"),
          build: { buffer, context in Self.row(model: model, capture: capture, into: &buffer, context: context) })
      ]
    )
    renderer.build = { buffer, context in
      buffer.onCommand(
        buffer.scrollView(scroll, context: context.keyed(WidgetID("stack"))), .application("resize"), context: context,
        action: {
          model.height = 80
          return .handled
        })
    }
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
      beginTestFrame(interaction, input: InputState())
      var list = DrawList()
      let stack = ScrollView(
        controller: controller,
        rows: [
          .init(
            id: WidgetID("stable-row"),
            build: { buffer, context in
              buffer.sizing(buffer.color(.white, context: context), y: .fixed(height), context: context)
            }
          )
        ]
      )
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(stack, context: LayoutContext(interaction: interaction).keyed(id))
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
      id: WidgetID("row"),
      build: { buffer, context in buffer.sizing(buffer.color(.white, context: context), y: .fixed(40), context: context)
      })
    func frame() {
      beginTestFrame(interaction, input: InputState())
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(controller: controller, rows: [row]), context: LayoutContext(interaction: interaction).keyed(id))
        resolvedBuffer.register(resolved, in: Rect(x: 0, y: 0, width: 100, height: 20))
        resolvedBuffer.paint(resolved, into: &list, in: Rect(x: 0, y: 0, width: 100, height: 20))
      }
      interaction.endFrame()
    }
    frame()
    row.build = { buffer, context in
      buffer.sizing(buffer.color(.white, context: context), y: .fixed(100), context: context)
    }
    frame()
    #expect(interaction.scrollState(for: id).limit.y == 80)
  }

  @Test func retainedRowUsesCurrentTextScaleAndFontMetrics() {
    let interaction = Interaction()
    let controller = ScrollViewController()
    let id = WidgetID("scroll")
    let rows = [
      ScrollView.Row(id: WidgetID("row"), build: { buffer, context in buffer.text(Text("row"), context: context) })
    ]
    func frame(scale: Float) {
      beginTestFrame(interaction, input: InputState())
      var list = DrawList()
      do {
        var resolvedBuffer = LayoutBuffer()
        let resolved = resolvedBuffer.scrollView(
          ScrollView(controller: controller, rows: rows),
          context: LayoutContext(interaction: interaction, textScale: scale).keyed(id))
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
