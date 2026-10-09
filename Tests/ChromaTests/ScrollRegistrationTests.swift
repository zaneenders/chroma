import ChromaTesting
import Observation
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct ScrollRegistrationTests {
  final class Capture {
    var bodies = 0
    var measurements: [Int] = []
    var proposals: [Size] = []
    var registered: [(index: Int, rect: Rect)] = []
    var paints = 0
  }

  @MainActor struct Probe: Block {

    func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        measure: { self.sizeThatFits($0, context: context) },
        register: { self.register(in: $0, context: context) },
        paint: { self.paint(into: &$0, in: $1, context: context) })
    }

    let index: Int
    let height: Float
    let capture: Capture
    var action: (@MainActor () -> Void)? = nil

    var focusRule: FocusRule { action == nil ? .standard : .control }

    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      capture.measurements.append(index)
      capture.proposals.append(proposal)
      return Size(width: proposal.width, height: height)
    }

    func register(in rect: Rect, context: BlockContext) {
      capture.registered.append((index, rect))
      if let action { context.registerFocusable(in: rect, action: action) }
    }

    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      capture.paints += 1
      list.fillRect(rect, color: .white)
      if action != nil { context.paintFocusHighlight(in: rect, into: &list) }
    }
  }

  @MainActor struct Composite: Block {
    let capture: Capture
    func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      buffer.emit(content(), context: context.component(Self.self))
    }
    func content() -> some Block {
      capture.bodies += 1
      return Probe(index: 0, height: 100, capture: capture)
    }
  }

  @Observable final class HeightModel {
    var height: Float = 10
  }

  @MainActor struct ObservableRow: Block {

    func emit(into buffer: inout LayoutBuffer, context: BlockContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        measure: { self.sizeThatFits($0, context: context) },
        register: { self.register(in: $0, context: context) },
        paint: { self.paint(into: &$0, in: $1, context: context) })
    }

    let model: HeightModel
    let capture: Capture
    var focusRule: FocusRule { .standard }

    @MainActor func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      capture.measurements.append(0)
      return Size(width: proposal.width, height: model.height)
    }

    func register(in rect: Rect, context: BlockContext) {
      capture.registered.append((0, rect))
    }

    func paint(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      capture.paints += 1
    }
  }

  @MainActor final class Harness {
    var context = BlockContext()
    let producer = FrameProducer()
    var viewport = Size(width: 100, height: 20)

    func register(_ content: any Block, commands: [Command] = []) {
      context.interaction.viewport = Rect(origin: .zero, size: viewport)
      producer.refreshRegistrations(
        { buffer, context in buffer.emit(content, context: context) }, viewport: viewport, context: context,
        commands: commands)
    }

    func send(_ input: InputState, to content: any Block) {
      register(content, commands: input.commands)
      context.interaction.processInput(input)
      context.interaction.finishInput()
    }

    /// Send a wheel event against the current registration, before rebuilding its placement.
    func wheel(by offset: Float) {
      context.interaction.processInput(
        InputState(pointerPosition: Point(x: 5, y: 5), scrollDelta: Point(x: 0, y: -offset)))
      context.interaction.finishInput()
    }

    func leaf(at point: Point) -> InteractionNode? {
      let tree = context.interaction.tree
      guard let path = tree?.hitTest(point) else { return nil }
      return tree?.node(at: path)
    }
  }

  @Test func ordinaryScrollSharesResolutionBetweenMeasurementAndRegistration() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let h = Harness()
    let capture = Capture()
    let controller = ScrollViewController()
    let content = ScrollView(showsIndicator: true, controller: controller) {
      Composite(capture: capture)
    }
    h.register(content)
    #expect(capture.bodies == 1)
    #expect(capture.measurements == [0, 0])
    #expect(
      capture.proposals == [
        Size(width: 100, height: .greatestFiniteMagnitude), Size(width: 100, height: 100),
      ])
    #expect(capture.registered.map(\.rect) == [Rect(x: 0, y: 0, width: 100, height: 100)])
    #expect(capture.paints == 0)
    #expect(h.leaf(at: Point(x: 5, y: 5)) != nil)
    #expect(h.leaf(at: Point(x: 5, y: 25)) == nil)

    h.wheel(by: 30)
    capture.registered = []
    h.register(content)
    #expect(capture.bodies == 2, "A new registration traversal must observe current content")
    #expect(capture.registered.map(\.rect) == [Rect(x: 0, y: -30, width: 100, height: 100)])
    #expect(capture.paints == 0)
    #expect(PipelineMetrics.snapshot.paints == 0)
    #expect(PipelineMetrics.snapshot.drawingCommands == 0)
  }

  @Test func uniformRegistrationBuildsOnlyVisibleRowsAndClipsFallbackFocus() {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let h = Harness()
    let capture = Capture()
    let controller = ScrollViewController()
    var built: [Int] = []
    let content = ScrollView(data: 0..<10_000, rowHeight: 10, controller: controller) { index in
      built.append(index)
      return Probe(index: index, height: 10, capture: capture)
    }
    h.register(content)
    #expect(built == [0, 1, 2])
    #expect(capture.registered.map(\.index) == built)
    #expect(capture.measurements.isEmpty)
    let firstLeaf = h.leaf(at: Point(x: 5, y: 5))?.leafID
    #expect(firstLeaf != nil)
    #expect(h.leaf(at: Point(x: 5, y: 25)) == nil)

    built = []
    capture.registered = []
    h.wheel(by: 50)
    h.register(content)
    #expect(built == [4, 5, 6, 7])
    #expect(capture.registered.map(\.rect.minY) == [-10, 0, 10, 20])
    #expect(h.leaf(at: Point(x: 5, y: 5))?.leafID != firstLeaf)
    #expect(h.leaf(at: Point(x: 5, y: -5)) == nil)
    #expect(h.leaf(at: Point(x: 5, y: 25)) == nil)
    #expect(capture.measurements.isEmpty)
    #expect(capture.paints == 0)
    #expect(PipelineMetrics.snapshot.paints == 0)
    #expect(PipelineMetrics.snapshot.drawingCommands == 0)
  }

  @Test func registrationPreservesPendingControllerRequestForPresentationOrdering() {
    let h = Harness()
    let capture = Capture()
    let controller = ScrollViewController()
    let content = ScrollView(data: 0..<30, rowHeight: 10, controller: controller) { index in
      Probe(index: index, height: 10, capture: capture)
    }
    h.register(content)
    controller.scroll(to: 50)
    h.register(content)
    #expect(controller.request == .offset(50))
    #expect(controller.offset == 0)
    #expect(capture.paints == 0)
  }

  @Test func registrationKeepsNavigationFocusBufferWithoutDispatchingCommands() {
    let h = Harness()
    let capture = Capture()
    let controller = ScrollViewController()
    let content = ScrollView(data: 0..<30, rowHeight: 10, controller: controller) { index in
      Probe(index: index, height: 10, capture: capture)
    }
    h.register(content)
    h.wheel(by: 50)
    capture.registered = []
    h.register(content, commands: [.navigation(.up), .navigation(.up), .navigation(.down)])
    #expect(capture.registered.map(\.index) == Array(2...8))
    #expect(h.context.interaction.selectedLeafID == nil)
    #expect(controller.offset == 50)
    #expect(capture.paints == 0)
  }

  @Test func variableRegistrationReusesMeasurementsAndTracksRowContentReplacement() {
    let h = Harness()
    let capture = Capture()
    let controller = ScrollViewController()
    let rows = (0..<5).map { ScrollView.Row(id: $0, content: Probe(index: $0, height: 10, capture: capture)) }
    func content(_ rows: [ScrollView.Row]) -> ScrollView {
      ScrollView(controller: controller, rows: rows)
    }
    h.register(content(rows))
    #expect(capture.measurements == Array(0..<5))
    let measurements = controller.lazyStackCache.measurements
    capture.measurements = []
    h.register(content(rows))
    #expect(capture.measurements.isEmpty)

    h.register(content([rows[2], rows[1], rows[0]]))
    #expect(capture.measurements.isEmpty)
    #expect(controller.lazyStackCache.measurements[0] === measurements[2])
    #expect(controller.lazyStackCache.measurements[2] === measurements[0])

    var replacement = rows[1]
    replacement.setContent(Probe(index: 1, height: 30, capture: capture))
    capture.registered = []
    h.register(content([rows[2], replacement, rows[0]]))
    #expect(capture.measurements == [1])
    #expect(controller.lazyStackCache.rowSizes.map(\.height) == [10, 30, 10])
    #expect(
      capture.registered.map(\.rect) == [
        Rect(x: 0, y: 0, width: 100, height: 10),
        Rect(x: 0, y: 10, width: 100, height: 30),
      ])
    #expect(capture.paints == 0)
  }

  @Test(arguments: ["width", "textScale", "fontMetrics", "theme", "identity"])
  func variableRegistrationInvalidatesChangedMeasurementEnvironment(change: String) {
    let h = Harness()
    let capture = Capture()
    let controller = ScrollViewController()
    let rows = (0..<3).map { ScrollView.Row(id: $0, content: Probe(index: $0, height: 10, capture: capture)) }
    func content(_ identity: Int) -> some Block {
      ScrollView(controller: controller, rows: rows).id(identity)
    }
    h.register(content(0))
    capture.measurements = []
    switch change {
    case "width": h.viewport.width = 200
    case "textScale": h.context.textScale = 2
    case "fontMetrics": h.context.fontMetrics.glyphHeight = 40
    case "theme": h.context.theme = .dark.accentColor(.white)
    case "identity": break
    default: Issue.record("Unexpected environment change")
    }
    h.register(content(change == "identity" ? 1 : 0))
    #expect(capture.measurements == [0, 1, 2])
    #expect(capture.paints == 0)
  }

  @Test func observableHeightChangeUpdatesRegistrationBeforeObservationDelivery() {
    let h = Harness()
    h.viewport.height = 100
    let capture = Capture()
    let controller = ScrollViewController()
    let model = HeightModel()
    let content = ScrollView(
      controller: controller,
      rows: [
        .init(id: 0, content: ObservableRow(model: model, capture: capture)),
        .init(id: 1, content: Probe(index: 1, height: 10, capture: capture)),
      ])
    h.register(content)
    capture.measurements = []
    capture.registered = []
    model.height = 40
    h.register(content)
    #expect(capture.measurements == [0])
    #expect(capture.registered.map(\.rect.minY) == [0, 40])
    #expect(capture.registered.map(\.rect.size.height) == [40, 10])
    #expect(capture.paints == 0)
  }

  @Test func explicitInvalidationUpdatesUnobservedRowHeightAndFollowingPlacement() {
    final class Model { var height: Float = 10 }
    let model = Model()
    let h = Harness()
    h.viewport.height = 100
    let capture = Capture()
    let controller = ScrollViewController()
    var first = ScrollView.Row(
      id: 0,
      content: DeferredBlock {
        Probe(index: 0, height: model.height, capture: capture)
      })
    let second = ScrollView.Row(id: 1, content: Probe(index: 1, height: 10, capture: capture))
    func content() -> ScrollView { ScrollView(controller: controller, rows: [first, second]) }
    h.register(content())
    capture.measurements = []
    capture.registered = []
    model.height = 40
    first.invalidateMeasurement()
    h.register(content())
    #expect(capture.measurements == [0])
    #expect(capture.registered.map(\.rect.minY) == [0, 40])
    #expect(capture.registered.map(\.rect.size.height) == [40, 10])
    #expect(capture.paints == 0)
  }

  @Test func cachedVariableMeasurementStillRefreshesCapturedActionsBetweenInputs() {
    let h = Harness()
    let capture = Capture()
    let controller = ScrollViewController()
    var actions = 0
    let row = ScrollView.Row(
      id: 0,
      content: DeferredBlock {
        let current = actions
        return Probe(index: 0, height: 10, capture: capture, action: { actions = current + 1 })
      })
    let content = ScrollView(controller: controller, rows: [row])
    h.register(content)
    h.context.interaction.focusFirstControlForTest()
    h.send(InputState(commands: [.action(.activate)]), to: content)
    h.send(InputState(commands: [.action(.activate)]), to: content)
    #expect(actions == 2)
    #expect(capture.measurements == [0])
    #expect(capture.paints == 0)
  }

  @Test func virtualizedReleaseUsesFreshActionAndRemovedPressCannotRevive() {
    let h = Harness()
    let capture = Capture()
    let controller = ScrollViewController()
    var actions: [String] = []
    func content(_ value: String) -> ScrollView {
      ScrollView(data: 0..<30, rowHeight: 10, controller: controller) { index in
        Probe(index: index, height: 10, capture: capture, action: { actions.append(value) })
      }
    }
    let point = Point(x: 5, y: 5)
    let press = InputState(
      pointerPosition: point, pointerPressPosition: point, pointerDown: true, pointerPressed: true)
    let release = InputState(pointerPosition: point, pointerReleased: true)
    h.send(press, to: content("old"))
    h.send(release, to: content("new"))
    #expect(actions == ["new"])

    h.send(press, to: content("old"))
    let pressed = h.context.interaction.pressedLeaf
    #expect(pressed != nil)
    h.wheel(by: 100)
    h.register(content("offscreen"))
    #expect(h.context.interaction.pressedLeaf == nil)
    h.wheel(by: -100)
    h.send(release, to: content("returned"))
    #expect(pressed.flatMap { h.context.interaction.tree?.findLeaf($0) } != nil)
    #expect(actions == ["new"])
    #expect(capture.paints == 0)
  }

  @Test func registrationFocusRecoveryDoesNotMoveNextPointerTarget() {
    let h = Harness()
    h.viewport.height = 100
    let capture = Capture()
    let controller = ScrollViewController()
    var actions: [Int] = []
    let content = ScrollView(data: 0..<30, rowHeight: 30, controller: controller) { index in
      Probe(index: index, height: 30, capture: capture, action: { actions.append(index) })
    }
    func click(_ point: Point) {
      h.send(
        InputState(pointerPosition: point, pointerPressPosition: point, pointerDown: true, pointerPressed: true),
        to: content)
      h.send(InputState(pointerPosition: point, pointerReleased: true), to: content)
    }
    click(Point(x: 5, y: 5))
    #expect(actions == [0])
    h.wheel(by: 800)
    h.register(content)
    #expect(controller.offset == 800)
    click(Point(x: 5, y: 80))
    #expect(controller.offset == 800)
    #expect(actions == [0, 29])
    #expect(capture.paints == 0)
  }
}
