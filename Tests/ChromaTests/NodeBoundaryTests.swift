import Observation
import Testing

@testable import Chroma

@MainActor
struct NodeBoundaryTests {
  @Observable final class Model {
    var label = "Run"
    var color = Color.white
    var revision = 0
    var visible = true
    var clipped = false
  }

  private final class Counts {
    var rows: [Int: Int] = [:]
    var panels: [Int: Int] = [:]
    var actions: [Int] = []
  }

  private let viewport = Size(width: 240, height: 160)

  private struct LegacyOnly: PrimitiveBlock {
    var focusRule: FocusRule { .decorative }
    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size { proposal }
    func draw(into drawList: inout DrawList, in rect: Rect, context: BlockContext) {}
  }

  @Test func oneObservedRowRebuildsWithoutRebuildingOtherRowsOrRoot() throws {
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let counts = Counts()
    let models = (0..<100).map { _ in Model() }
    let content = FixedHeightList(count: 100, rowHeight: 40, overscan: 0) { index in
      counts.rows[index, default: 0] += 1
      let revision = models[index].revision
      return Button(models[index].label) { counts.actions.append(revision) }
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    let layouts = producer.layouts
    let measurements = producer.measurements
    models[1].revision = 1
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(counts.rows == [0: 1, 1: 2, 2: 1, 3: 1])
    #expect(producer.builds == 1)
    #expect(producer.layouts == layouts)
    #expect(producer.measurements == measurements)
    let point = Point(x: 10, y: 50)
    try producer.dispatch(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true), onChange: {})
    try producer.dispatch(InputState(pointerPosition: point, pointerReleased: true), onChange: {})
    #expect(counts.actions == [1])
    #expect(producer.paints == 0)
  }

  @Test func panelPaintLayoutAndStructuralUpdatesAreIndependent() throws {
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let left = Model()
    let right = Model()
    let counts = Counts()
    let content = HStack(spacing: 4) {
      UpdateBoundary {
        counts.panels[0, default: 0] += 1
        return Text(left.label).foregroundColor(left.color)
      }
      UpdateBoundary {
        counts.panels[1, default: 0] += 1
        return VStack {
          if right.visible { Button(right.label) {} }
        }
      }
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    let layouts = producer.layouts
    let measurements = producer.measurements
    let preparations = producer.preparations
    left.color = .black
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(counts.panels == [0: 2, 1: 1])
    #expect(producer.layouts == layouts)
    #expect(producer.measurements == measurements)
    #expect(producer.preparations == preparations)
    left.label = "Changed width"
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(counts.panels == [0: 3, 1: 1])
    #expect(producer.layouts == layouts + 1)
    #expect(producer.measurements > measurements)
    right.visible = false
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(context.interaction.registrations.buttonActions.isEmpty)
    #expect(counts.panels == [0: 3, 1: 2])
    #expect(producer.builds == 1)
    #expect(producer.paints == 0)
  }

  @Test func nestedPanelWidthChangesInvalidateMeasuredAncestors() throws {
    let model = Model()
    let context = BlockContext()
    let producer = NodeFrameProducer()
    let content = UpdateBoundary {
      HStack(spacing: 10) {
        UpdateBoundary { Text(model.label) }
        Text("Sibling")
      }
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    let initial = producer.paint().commands
    let firstPosition = initial.compactMap { command -> Point? in
      if case .text(let point, "Sibling", _, _) = command { point } else { nil }
    }.first
    model.label = "Longer label"
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    let changedPosition = producer.paint().commands.compactMap { command -> Point? in
      if case .text(let point, "Sibling", _, _) = command { point } else { nil }
    }.first
    #expect(try #require(changedPosition).x > #require(firstPosition).x)
    #expect(producer.builds == 1)
  }

  @Test func rowPaintChangesDoNotRefreshLayoutOrInteraction() throws {
    let model = Model()
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let content = FixedHeightList(count: 4, rowHeight: 40, overscan: 0) { index in
      Text("Row \(index)").foregroundColor(index == 1 ? model.color : .white)
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    let preparations = producer.preparations
    let layouts = producer.layouts
    let measurements = producer.measurements
    model.color = .black
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(producer.preparations == preparations)
    #expect(producer.layouts == layouts)
    #expect(producer.measurements == measurements)
    #expect(
      producer.paint().commands.contains {
        if case .text(_, "Row 1", .black, _) = $0 { true } else { false }
      })
  }

  @Test func panelInsideRowUsesSeparateTrackingAndParentUpdatesReplaceCallbacks() throws {
    let row = Model()
    let panel = Model()
    let counts = Counts()
    let context = BlockContext()
    let producer = NodeFrameProducer()
    let content = FixedHeightList(count: 4, rowHeight: 40, overscan: 0) { index in
      counts.rows[index, default: 0] += 1
      let revision = row.revision
      return UpdateBoundary {
        counts.panels[index, default: 0] += 1
        return Button(panel.label) { counts.actions.append(revision) }
      }
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    panel.label = "New"
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(counts.rows == [0: 1, 1: 1, 2: 1, 3: 1])
    #expect(counts.panels == [0: 2, 1: 2, 2: 2, 3: 2])
    row.revision = 2
    panel.label = "Both stale"
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(counts.rows == [0: 2, 1: 2, 2: 2, 3: 2])
    #expect(counts.panels == [0: 3, 1: 3, 2: 3, 3: 3])
    try producer.dispatch(InputState(commands: [.navigation(.nextFocus)]), onChange: {})
    try producer.dispatch(InputState(commands: [.action(.activate)]), onChange: {})
    #expect(counts.actions == [2])
  }

  @Test func clippingChangesRefreshHitGeometryWithoutRelayout() throws {
    let model = Model()
    let producer = NodeFrameProducer()
    let context = BlockContext()
    func clippedContent(_ clipped: Bool) -> any Block {
      let text = Text("Overflow").sizing(x: .fixed(20), y: .fixed(20))
      return clipped ? text.padding(20).clipped() : text.clipped().padding(20)
    }
    let content = UpdateBoundary { clippedContent(model.clipped) }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    let layouts = producer.layouts
    let preparations = producer.preparations
    model.clipped = true
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(producer.layouts == layouts)
    #expect(producer.preparations == preparations + 1)
  }

  @Test func unsupportedPanelUpdateDoesNotReplaceCommittedOutput() throws {
    let model = Model()
    let context = BlockContext()
    let producer = NodeFrameProducer()
    let content = UpdateBoundary {
      if model.visible { Text("Retained") } else { LegacyOnly() }
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    let before = producer.paint().commands
    model.visible = false
    #expect(throws: NodeScene.BuildError.self) {
      try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    }
    #expect(producer.paint().commands == before)
  }

  @Test func removedPanelTrackingAndCallbacksAreReleasedBeforeNextInput() throws {
    let row = Model()
    let panel = Model()
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let counts = Counts()
    let content = FixedHeightList(count: 1, rowHeight: 40, overscan: 0) { _ in
      if row.visible {
        return UpdateBoundary {
          counts.panels[0, default: 0] += 1
          return Button(panel.label) { counts.actions.append(1) }
        }
      }
      return Text("Removed")
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    row.visible = false
    panel.label = "Also stale"
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(context.interaction.registrations.buttonActions.isEmpty)
    #expect(counts.panels == [0: 1])
    let boundaryBuilds = producer.boundaryBuilds
    panel.label = "Unmounted"
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(producer.boundaryBuilds == boundaryBuilds)
    try producer.dispatch(InputState(commands: [.action(.activate)]), onChange: {})
    #expect(counts.actions.isEmpty)
  }

  @Test func keyedRowIdentityRefreshesChangedStructuralRootWithoutRebuildingSiblings() throws {
    let model = Model()
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let counts = Counts()
    let content = FixedHeightList(count: 2, rowHeight: 40, overscan: 0) { index in
      counts.rows[index, default: 0] += 1
      return VStack {
        if index != 0 || model.visible { Button("Run") { counts.actions.append(index) } } else { Text("Removed") }
      }
    }
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    model.visible = false
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(counts.rows == [0: 2, 1: 1])
    #expect(context.interaction.registrations.buttonActions.count == 1)
    #expect(producer.builds == 1)
  }

  @Test func rootObservationReplacesBoundariesWithoutReusingTheirOldBuilders() throws {
    let model = Model()
    let context = BlockContext()
    let producer = NodeFrameProducer()
    let content = RootContent(model: model)
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    model.revision = 1
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(producer.builds == 2)
    model.label = "Changed"
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(producer.builds == 2)
    #expect(
      producer.paint().commands.contains {
        if case .text(_, "1-Changed", _, _) = $0 { true } else { false }
      })
  }

  private struct RootContent: Block {
    let model: Model
    var body: some Block {
      let revision = model.revision
      return UpdateBoundary { Text("\(revision)-\(model.label)") }
    }
  }

  private final class LifetimeProbe {}

  @Test func scrollingReleasesNestedBoundaryBuildersAndSubmittedFramesStayOwned() throws {
    let scene = NodeScene()
    let context = BlockContext()
    weak var removed: LifetimeProbe?
    try scene.update(
      FixedHeightList(count: 100, rowHeight: 40, overscan: 0) { index in
        let probe = LifetimeProbe()
        if index == 0 { removed = probe }
        return UpdateBoundary {
          Button("Row \(index)") { [probe] in _ = probe }
        }
      }, context: context)
    try scene.layout(in: Rect(origin: .zero, size: viewport))
    scene.prepare(viewport: viewport)
    let submitted = scene.paint()
    #expect(removed != nil)
    for _ in 0..<20 {
      try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -160)))
      #expect(scene.liveCount == 13)
      #expect(scene.slotCount <= 25)
    }
    #expect(removed == nil)
    #expect(
      submitted.commands.contains {
        if case .text(_, "Row 0", _, _) = $0 { true } else { false }
      })
  }

  @Test func legacyBoundaryRendersAndMeasuresWithoutNodeLifecycle() {
    let context = BlockContext()
    let content = UpdateBoundary { Text("Legacy") }
    #expect(BlockEngine.measure(content, proposal: viewport, context: context) == context.fontMetrics.measure("Legacy"))
    var list = DrawList()
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    BlockEngine.draw(content, into: &list, in: Rect(origin: .zero, size: viewport), context: context)
    context.interaction.endFrame()
    #expect(
      list.commands.contains {
        if case .text(_, "Legacy", _, _) = $0 { true } else { false }
      })
  }
}
