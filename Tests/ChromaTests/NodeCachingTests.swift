import Observation
import Testing

@testable import Chroma

@MainActor
struct NodeCachingTests {
  private let rect = Rect(x: 0, y: 0, width: 240, height: 160)

  @Test func callbackAndPaintChangesReuseMeasurementsButRefreshActions() throws {
    let context = BlockContext()
    let scene = NodeScene()
    var actions: [Int] = []
    func content(_ revision: Int) -> some Block {
      VStack {
        Button("Run") { actions.append(revision) }
        Text("Stable").foregroundColor(revision == 0 ? .white : .black)
      }
    }
    try scene.update(content(0), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.dispatch(InputState(commands: [.navigation(.nextFocus)]))
    let measurements = scene.measurements
    let layouts = scene.layouts
    try scene.update(content(1), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.dispatch(InputState(commands: [.action(.activate)]))
    #expect(actions == [1])
    #expect(scene.measurements == measurements)
    #expect(scene.layouts == layouts)
    #expect(
      scene.paint().commands.contains {
        if case .text(_, "Stable", .black, _) = $0 { true } else { false }
      })
  }

  @Test func changedContentInvalidatesOnlyItsMeasurementAndAncestors() throws {
    let scene = NodeScene()
    let context = BlockContext()
    func content(_ label: String) -> VStack {
      VStack {
        Text(label).id("changed")
        Text("Unchanged").id("stable")
      }
    }
    try scene.update(content("Old"), context: context)
    try scene.layout(in: rect)
    let count = scene.measurements
    try scene.update(content("New content"), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(scene.measurements == count + 2)
    #expect(
      scene.paint().commands.contains {
        if case .text(_, "New content", _, _) = $0 { true } else { false }
      })
  }

  @Test func constraintsAndLayoutEnvironmentInvalidateCachedMeasurements() throws {
    let scene = NodeScene()
    var context = BlockContext()
    let text = Text("one two three four").wrapping()
    try scene.update(text, context: context)
    let initial = try scene.layout(in: rect)
    let count = scene.measurements
    #expect(try scene.layout(in: rect) == initial)
    #expect(scene.measurements == count)
    let narrow = Rect(x: 0, y: 0, width: 60, height: 160)
    #expect(try scene.layout(in: narrow).height > initial.height)
    let narrowCount = scene.measurements
    context.fontMetrics.lineAdvance *= 2
    #expect(try scene.layout(in: narrow).height > initial.height)
    #expect(scene.measurements == narrowCount + 1)
    context.textScale = 2
    try scene.update(text, context: context)
    try scene.layout(in: narrow)
    #expect(scene.measurements == narrowCount + 2)
  }

  private final class BuildCounter {
    var builds = 0
  }

  private struct CountedContent: Block {
    let counter: BuildCounter
    var body: some Block {
      counter.builds += 1
      return Button("Run") {}
    }
  }

  @Test func resizeHoverFocusAndPaintDoNotEvaluateBlocks() throws {
    let counter = BuildCounter()
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let content = CountedContent(counter: counter)
    try producer.refresh(content: content, viewport: rect.size, context: context, onChange: {})
    let measurements = producer.measurements
    let layouts = producer.layouts
    let preparations = producer.preparations
    try producer.dispatch(InputState(pointerPosition: Point(x: 10, y: 10)), onChange: {})
    try producer.dispatch(InputState(commands: [.navigation(.nextFocus)]), onChange: {})
    _ = producer.paint()
    _ = producer.paint()
    #expect(producer.measurements == measurements)
    #expect(producer.layouts == layouts)
    #expect(producer.preparations == preparations)
    try producer.refresh(content: content, viewport: Size(width: 300, height: 180), context: context, onChange: {})
    #expect(counter.builds == 1)
    #expect(producer.builds == 1)
    #expect(context.interaction.viewport.size == Size(width: 300, height: 180))
  }

  @Test func orderedModifiersMatchLegacyAndPreserveFocusIdentity() throws {
    let context = BlockContext()
    let scene = NodeScene()
    let variants: [any Block] = [
      Text("Text").padding(8).background(Color.black).border(.white),
      Text("Text").background(Color.black).padding(8).roundedBorder(.white, radius: 4),
      Text("Text").padding(4).roundedBackground(.black, radius: 3).padding(7).clipped(),
      HStack {
        Text("Text").padding(4)
        Spacer()
        Button("Run") {}.sizing(x: .grow)
      }.padding(3).background(Color.black),
      ZStack {
        Color.black.sizing(x: .fixed(100), y: .fixed(60))
        Text("Overlay").padding(2)
      },
    ]
    for content in variants {
      try scene.update(content, context: context)
      let size = try scene.layout(in: rect)
      #expect(size == BlockEngine.measure(content, proposal: rect.size, context: context))
      scene.prepare(viewport: rect.size)
      let expected = scene.paint(cullingEnabled: false)
      context.interaction.beginFrame(input: InputState(), processingInput: false)
      var legacy = DrawList()
      BlockEngine.draw(content, into: &legacy, in: rect, context: context)
      context.interaction.endFrame()
      #expect(expected.commands == legacy.commands)
    }
    try scene.update(Button("Run") {}.padding(3), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.dispatch(InputState(commands: [.navigation(.nextFocus)]))
    let selected = try #require(context.interaction.selectedLeafID)
    try scene.update(Button("Run") {}.background(Color.black).padding(8).border(.white), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(context.interaction.selectedLeafID == selected)
    #expect(scene.liveCount == 1)
  }

  @Test func changingFlexiblePrimitiveRecomputesStackCrossExtent() throws {
    let scene = NodeScene()
    let context = BlockContext()
    func content(_ child: any Block) -> HStack { HStack { child } }
    try scene.update(content(Color.black), context: context)
    #expect(try scene.layout(in: rect).height == rect.size.height)
    try scene.update(content(Spacer()), context: context)
    #expect(try scene.layout(in: rect).height == 0)
  }

  @Test func paintModifierChangesDoNotRelayoutOrKeepStaleDecorationRects() throws {
    let scene = NodeScene()
    let context = BlockContext()
    try scene.update(Text("Run").padding(3), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let layouts = scene.layouts
    try scene.update(Text("Run").background(Color.black).padding(3).border(.white), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(scene.layouts == layouts)
    let commands = scene.paint().commands
    #expect(commands.contains(.fillRect(rect: Rect(x: 3, y: 3, width: 234, height: 154), color: .black)))
    #expect(commands.contains(.strokeRect(rect: rect, width: 1, color: .white)))
  }

  @Test func cullingPreservesOverflowOverlaysReversedAndNestedLists() throws {
    let content: [any Block] = [
      VStack(spacing: -40) {
        Text("Above").sizing(y: .fixed(200))
        Text("Visible despite parent extent").sizing(y: .fixed(0))
      }.reverseLayout(),
      ZStack {
        VStack {
          Text("First").sizing(y: .fixed(200))
          Text("Invisible")
        }
        Text("Visible overlay")
      },
      FixedHeightList(count: 100, rowHeight: 40, overscan: 2) { index in
        if index % 2 == 0 {
          FixedHeightList(count: 10, rowHeight: 20) { Text("Nested \($0)") }
        } else {
          Text("Row \(index)").padding(2).clipped()
        }
      },
      VStack {
        Text("Large glyph overflow").fontScale(2).sizing(x: .fixed(0), y: .fixed(0))
        Text("Second").sizing(y: .fixed(200))
        Text("Offscreen")
      },
    ]
    for block in content {
      let scene = NodeScene()
      let context = BlockContext()
      try scene.update(block, context: context)
      try scene.layout(in: rect)
      scene.prepare(viewport: rect.size)
      let tree = context.interaction.tree
      let culled = scene.paint().culled(to: rect.size)
      let unculled = scene.paint(cullingEnabled: false).culled(to: rect.size)
      func visible(_ list: DrawList) -> [DrawCommand] {
        list.commands.filter {
          switch $0 {
          case .pushClip, .popClip: false
          default: true
          }
        }
      }
      #expect(visible(culled) == visible(unculled))
      #expect(context.interaction.tree === tree)
    }
  }

  @Test func offscreenSubtreesAreNotVisitedAndNavigationIsRetained() throws {
    let scene = NodeScene()
    let context = BlockContext()
    try scene.update(
      VStack {
        ForEach(0..<100, id: \.self) { Text("Row \($0)") }
      }, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let before = scene.paintVisits
    _ = scene.paint()
    let culledVisits = scene.paintVisits - before
    let unculledStart = scene.paintVisits
    _ = scene.paint(cullingEnabled: false)
    #expect(culledVisits < 10)
    #expect(scene.paintVisits - unculledStart == 101)
    #expect(context.interaction.tree?.children.first?.children.count == 100)
  }

  @Observable final class Model {
    var color = Color.white
    var label = "Row"
  }

  @Test func observedPaintChangesReuseLayoutAndResizeTracksNewRows() throws {
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let model = Model()
    let content = ObservedContent(model: model)
    try producer.refresh(content: content, viewport: rect.size, context: context, onChange: {})
    let layouts = producer.layouts
    let measurements = producer.measurements
    model.color = .black
    try producer.refresh(content: content, viewport: rect.size, context: context, onChange: {})
    #expect(producer.builds == 2)
    #expect(producer.layouts == layouts)
    #expect(producer.measurements == measurements)
    let rowModels = (0..<10).map { _ in Model() }
    let rows = FixedHeightList(count: 10, rowHeight: 40, overscan: 0) { Text(rowModels[$0].label) }
    producer.clear()
    try producer.refresh(content: rows, viewport: Size(width: 200, height: 40), context: context, onChange: {})
    let builds = producer.builds
    try producer.refresh(content: rows, viewport: Size(width: 200, height: 80), context: context, onChange: {})
    #expect(producer.builds == builds)
    rowModels[1].label = "Changed after resize"
    try producer.refresh(content: rows, viewport: Size(width: 200, height: 80), context: context, onChange: {})
    #expect(producer.builds == builds)
    #expect(
      producer.paint().commands.contains {
        if case .text(_, "Changed after resize", _, _) = $0 { true } else { false }
      })
  }

  @Test func nestedRowsKeepIndependentObservationAndUnmountCancelsTracking() throws {
    let producer = NodeFrameProducer()
    let context = BlockContext()
    let models = (0..<10).map { _ in Model() }
    let content = VStack {
      FixedHeightList(count: 10, rowHeight: 40, overscan: 0) { Text(models[$0].label) }
        .sizing(y: .fixed(80))
      FixedHeightList(count: 10, rowHeight: 40, overscan: 0) { Text("Other \($0)") }
        .sizing(y: .fixed(80))
    }
    try producer.refresh(content: content, viewport: rect.size, context: context, onChange: {})
    try producer.dispatch(
      InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -80)), onChange: {})
    try producer.dispatch(
      InputState(pointerPosition: Point(x: 10, y: 100), scrollDelta: Point(x: 0, y: -80)), onChange: {})
    let builds = producer.builds
    models[2].label = "Updated first list"
    try producer.refresh(content: content, viewport: rect.size, context: context, onChange: {})
    #expect(producer.builds == builds)
    #expect(
      producer.paint().commands.contains {
        if case .text(_, "Updated first list", _, _) = $0 { true } else { false }
      })
    let scene = NodeScene()
    try scene.update(FixedHeightList(count: 1, rowHeight: 40) { _ in Text(models[0].label) }, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.update(EmptyBlock(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    models[0].label = "Removed"
    #expect(scene.boundariesAreValid)
  }

  private struct ObservedContent: Block {
    let model: Model
    var body: some Block { Text("Stable").foregroundColor(model.color) }
  }

  private final class LifetimeProbe {}

  @Test func removedCallbacksAreReleasedAndScrollingReusesSlots() throws {
    let scene = NodeScene()
    let context = BlockContext()
    var probe: LifetimeProbe? = LifetimeProbe()
    weak let weakProbe = probe
    try scene.update(Button("Run") { [probe] in _ = probe }, context: context)
    probe = nil
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(weakProbe != nil)
    try scene.update(EmptyBlock(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(weakProbe == nil)
    weak var removedRow: LifetimeProbe?
    try scene.update(
      FixedHeightList(count: 10000, rowHeight: 40, overscan: 0) { index in
        let probe = LifetimeProbe()
        if index == 0 { removedRow = probe }
        return Button("Row \(index)") { [probe] in _ = probe }
      }, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(removedRow != nil)
    for _ in 0..<100 {
      try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -160)))
      #expect(scene.liveCount == 5)
      #expect(scene.slotCount <= 9)
    }
    #expect(removedRow == nil)
    let submitted = scene.paint()
    try scene.update(EmptyBlock(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(!submitted.commands.isEmpty)
    #expect(scene.liveCount == 1)
    let slots = scene.slotCount
    for _ in 0..<100 {
      try scene.update(VStack { Button("Mounted") {} }, context: context)
      try scene.layout(in: rect)
      scene.prepare(viewport: rect.size)
      try scene.update(EmptyBlock(), context: context)
      try scene.layout(in: rect)
      scene.prepare(viewport: rect.size)
      #expect(scene.liveCount == 1)
      #expect(scene.slotCount == slots)
    }
  }
}
