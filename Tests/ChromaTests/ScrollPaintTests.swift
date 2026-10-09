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

  @MainActor private struct Row: Block {

    func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        measure: { self.sizeThatFits($0, context: context) },
        register: { self.register(in: $0, context: context) },
        paint: { self.paint(into: &$0, in: $1, context: context) })
    }

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

  private struct Wrapper: Block {
    let content: any Block
    @MainActor func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      buffer.emit(content, context: context.component(Self.self))
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
      _ = producer.render(
        build: { buffer, context in buffer.emit(view, context: context) }, viewport: viewport.size, input: InputState(),
        context: context, onChange: {})
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
    var buffer = LayoutBuffer()
    let root = buffer.emit(view, context: context)
    beginTestFrame(interaction, input: InputState(pointerPosition: Point(x: -10, y: -10)))
    buffer.register(root, in: viewport)
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
    buffer.paint(root, into: &list, in: viewport)

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
    #expect(interaction.tree == tree)
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

    func register(in buffer: inout LayoutBuffer) -> LayoutNode {
      let root = buffer.emit(view, context: context)
      beginTestFrame(context.interaction, input: InputState())
      buffer.register(root, in: viewport)
      context.interaction.endFrame()
      return root
    }

    var buffer = LayoutBuffer()
    let root = register(in: &buffer)
    let measurements = controller.lazyStackCache.measurements
    let layout = controller.lazyStackCache.layout
    #expect(capture.measured == [0, 1])
    height.value = 40
    #expect(!measurements[0].valid)
    var list = DrawList()
    buffer.paint(root, into: &list, in: viewport)
    #expect(capture.measured == [0, 1])
    #expect(capture.registered == [0, 1])
    #expect(capture.painted.map(\.rect.size.height) == [10, 10])
    #expect(controller.lazyStackCache.layout == layout)
    #expect(controller.lazyStackCache.measurements[0] === measurements[0])
    #expect(!controller.lazyStackCache.measurements[0].valid)

    capture.painted = []
    var nextBuffer = LayoutBuffer()
    let next = register(in: &nextBuffer)
    nextBuffer.paint(next, into: &list, in: viewport)
    #expect(capture.measured == [0, 1, 0])
    #expect(capture.painted.map(\.index) == [0])
    #expect(capture.painted.map(\.rect.size.height) == [40])
    #expect(controller.lazyStackCache.measurements[0] !== measurements[0])
    #expect(controller.lazyStackCache.measurements[1] === measurements[1])
  }

  @Test func ordinaryPaintReusesEmittedContentAndReleasesItAfterOperation() {
    @MainActor struct Content: Block {
      let capture: Capture
      func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
        buffer.emit(content(), context: context.component(Self.self))
      }
      func content() -> some Block {
        capture.built.append(0)
        let lifetime = Lifetime()
        capture.lastRowLifetime = lifetime
        return Row(index: 0, capture: capture, lifetime: lifetime).sizing(y: .fixed(100))
      }
    }
    let context = BlockContext()
    let capture = Capture()
    let view = ScrollView(showsIndicator: false) { Content(capture: capture) }
    do {
      var buffer = LayoutBuffer()
      let root = buffer.emit(view, context: context)
      beginTestFrame(context.interaction, input: InputState())
      buffer.register(root, in: viewport)
      context.interaction.endFrame()
      let measurements = capture.measured
      var list = DrawList()
      buffer.paint(root, into: &list, in: viewport)
      #expect(capture.built == [0])
      #expect(capture.lastRowLifetime != nil)
      #expect(capture.measured == measurements)
      #expect(capture.registered == [0])
      #expect(capture.painted.map(\.rect) == [Rect(x: 0, y: 0, width: 100, height: 100)])
    }
    #expect(capture.lastRowLifetime == nil)
  }
}
