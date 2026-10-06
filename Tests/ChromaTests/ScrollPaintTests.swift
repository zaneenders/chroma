import ChromaTesting
import Observation
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct ScrollPaintTests {
  private let viewport = Rect(x: 0, y: 0, width: 100, height: 20)
  private let scrollID = WidgetID("paint-scroll")

  private final class Lifetime {}

  private final class Capture {
    var built: [Int] = []
    var measured: [Int] = []
    var registered: [Int] = []
    var painted: [(index: Int, rect: Rect)] = []
    weak var lastRowLifetime: Lifetime?
  }

  @Observable final class Height {
    var value: Float = 10
  }

  private struct Row: PaintableBlock {
    let index: Int
    let capture: Capture
    var height: Height? = nil
    var lifetime: Lifetime? = nil
    var focusRule: FocusRule { .standard }

    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      capture.measured.append(index)
      return Size(width: proposal.width, height: height?.value ?? 10)
    }

    func register(in rect: Rect, context: BlockContext) {
      capture.registered.append(index)
    }

    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      capture.painted.append((index, rect))
      list.fillRect(rect, color: .white)
    }

  }

  private struct Wrapper: LayoutPreparingBlock {
    let content: any Block
    var focusRule: FocusRule { .container }
    func prepareLayout(context: BlockContext) -> BlockEngine.Resolved {
      let child = BlockEngine.prepare(content, context: context)
      return BlockEngine.Resolved(measure: { $0 }, register: child.register, paint: child.paint)
    }
  }

  @Test func frameProducerReusesScrollPreparedThroughCustomWrapper() {
    let context = BlockContext()
    let producer = FrameProducer()
    let controller = ScrollViewController()
    let capture = Capture()
    let view = Wrapper(
      content: ScrollView(data: 0..<10_000, rowHeight: 10, controller: controller) { index in
        capture.built.append(index)
        let lifetime = Lifetime()
        capture.lastRowLifetime = lifetime
        return Row(index: index, capture: capture, lifetime: lifetime)
      })
    func render() {
      _ = producer.render(content: view, viewport: viewport.size, input: InputState(), context: context, onChange: {})
    }
    render()
    #expect(capture.lastRowLifetime == nil)
    capture.built = []
    capture.registered = []
    capture.painted = []
    render()
    #expect(capture.built == [0, 1, 2])
    #expect(capture.registered == [0, 1, 2])
    #expect(capture.painted.map(\.index) == [0, 1, 2])
    #expect(capture.measured.isEmpty)
    #expect(capture.lastRowLifetime == nil)
  }

  @Test func uniformPaintUsesPreparedRowsWithoutChangingInteractionOrController() throws {
    let context = BlockContext()
    let interaction = context.interaction
    let controller = ScrollViewController()
    let capture = Capture()
    let view = ScrollView(data: 0..<10_000, rowHeight: 10, controller: controller) { index in
      capture.built.append(index)
      return Row(index: index, capture: capture)
    }.id(scrollID)
    let resolved = BlockEngine.resolve(view, context: context)
    interaction.beginFrame(input: InputState(pointerPosition: Point(x: -10, y: -10)))
    resolved.register(in: viewport)
    interaction.endFrame()
    #expect(capture.built == [0, 1, 2])
    #expect(capture.registered == [0, 1, 2])
    #expect(capture.painted.isEmpty)

    let registeredID = try #require(interaction.scrollStates.keys.first)
    let state = try #require(interaction.scrollStates[registeredID])
    let tree = interaction.tree
    let reveal = Rect(x: 0, y: 500, width: 100, height: 10)
    let focus = Interaction.PendingFocus(leaf: WidgetID("pending-row"), scrollID: registeredID)
    interaction.scrollStates[registeredID]?.pendingReveal = reveal
    interaction.pendingFocus = focus
    controller.scrollToBottom()
    controller.offset = 17
    controller.horizontalOffset = 9
    interaction.building = Interaction.FrameRegistrations()
    interaction.buildingLogicalSelections = [:]

    var list = DrawList()
    resolved.paint(into: &list, in: viewport)

    #expect(capture.built == [0, 1, 2])
    #expect(capture.measured.isEmpty)
    #expect(capture.registered == [0, 1, 2])
    #expect(capture.painted.map(\.index) == [0, 1, 2])
    #expect(capture.painted.map(\.rect.minY) == [0, 10, 20])
    #expect(list.paintSnapshot.first == .pushClip(viewport))
    #expect(list.paintSnapshot.last == .popClip)
    #expect(controller.request == .bottom)
    #expect(controller.offset == 17)
    #expect(controller.horizontalOffset == 9)
    #expect(interaction.scrollStates[registeredID]?.offset == state.offset)
    #expect(interaction.scrollStates[registeredID]?.limit == state.limit)
    #expect(interaction.scrollStates[registeredID]?.layout == state.layout)
    #expect(interaction.scrollStates[registeredID]?.rows == state.rows)
    #expect(interaction.scrollStates[registeredID]?.rowKeys == state.rowKeys)
    #expect(interaction.scrollStates[registeredID]?.pendingReveal == reveal)
    #expect(interaction.pendingFocus == focus)
    #expect(interaction.tree === tree)
    #expect(interaction.builderRoot == nil)
    #expect(interaction.builderStack.isEmpty)
    #expect(interaction.clipStack.isEmpty)
    #expect(interaction.building.inputHandlers.isEmpty)
    #expect(interaction.building.buttonActions.isEmpty)
    #expect(interaction.building.focusTargets.isEmpty)
    #expect(interaction.buildingLogicalSelections.isEmpty)
  }

  @Test func variablePaintDoesNotRefreshInvalidatedMeasurementsOrPlacements() {
    let context = BlockContext()
    let controller = ScrollViewController()
    let capture = Capture()
    let height = Height()
    let view = ScrollView(
      showsIndicator: false, controller: controller,
      rows: [
        .init(id: 0, content: Row(index: 0, capture: capture, height: height)),
        .init(id: 1, content: Row(index: 1, capture: capture)),
      ]
    ).id(scrollID)

    func register() -> BlockEngine.Resolved {
      let resolved = BlockEngine.resolve(view, context: context)
      context.interaction.beginFrame(input: InputState())
      resolved.register(in: viewport)
      context.interaction.endFrame()
      return resolved
    }

    let resolved = register()
    let sizes = controller.rowGeometry.rowSizes
    let layout = controller.rowGeometry.layout
    #expect(capture.measured == [0, 1])
    height.value = 40
    var list = DrawList()
    resolved.paint(into: &list, in: viewport)
    #expect(capture.measured == [0, 1])
    #expect(capture.registered == [0, 1])
    #expect(capture.painted.map(\.rect.size.height) == [10, 10])
    #expect(controller.rowGeometry.layout == layout)
    #expect(controller.rowGeometry.rowSizes == sizes)

    capture.painted = []
    let next = register()
    next.paint(into: &list, in: viewport)
    #expect(capture.measured == [0, 1, 0, 1])
    #expect(capture.painted.map(\.index) == [0])
    #expect(capture.painted.map(\.rect.size.height) == [40])
    #expect(controller.rowGeometry.rowSizes.map(\.height) == [40, 10])
  }

  @Test func ordinaryPaintReusesMeasuredBodyAndReleasesPreparedContentAfterOperation() {
    struct Content: Block {
      let capture: Capture
      var body: some Block {
        capture.built.append(0)
        return Row(index: 0, capture: capture).sizing(y: .fixed(100))
      }
    }
    let context = BlockContext()
    let capture = Capture()
    let view = ScrollView(showsIndicator: false) { Content(capture: capture) }
    weak var retained: BlockEngine.Resolved?
    do {
      let resolved = BlockEngine.resolve(view, context: context)
      retained = resolved
      context.interaction.beginFrame(input: InputState())
      resolved.register(in: viewport)
      context.interaction.endFrame()
      let measurements = capture.measured
      var list = DrawList()
      resolved.paint(into: &list, in: viewport)
      #expect(capture.built == [0])
      #expect(capture.measured == measurements)
      #expect(capture.registered == [0])
      #expect(capture.painted.map(\.rect) == [Rect(x: 0, y: 0, width: 100, height: 100)])
    }
    #expect(retained == nil)
  }
}
