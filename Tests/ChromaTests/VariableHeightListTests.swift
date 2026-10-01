import Testing

@testable import Chroma

@MainActor
struct VariableHeightListTests {
  @Test func farScrollingBuildsAndMeasuresOnlyRequiredRows() throws {
    let snapshot = VirtualListSnapshot(ids: 0..<1_000_000)
    let scene = NodeScene()
    let context = BlockContext()
    var built: [Int] = []
    let list = VariableHeightList(snapshot: snapshot, estimatedHeight: 20, overscan: 0) { id in
      built.append(id)
      return Text("\(id)").sizing(y: .fixed(20))
    }
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(list, context: context)
    #expect(built.isEmpty)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(built == [0, 1])
    try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -10_000_000)))
    #expect(built == [0, 1, 500_000, 500_001])
    let measurements = scene.measurements
    for _ in 0..<8 {
      try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10)))
      _ = try scene.layout(in: rect)
      _ = scene.paint()
    }
    #expect(scene.measurements == measurements)
    #expect(built.count == 4)
    #expect(scene.liveCount <= 5)
  }

  @Test func shortRowsExpandUntilViewportIsFilled() throws {
    let scene = NodeScene()
    let context = BlockContext()
    var built: [Int] = []
    try scene.update(
      VariableHeightList(snapshot: VirtualListSnapshot(ids: 0..<100), estimatedHeight: 40, overscan: 0) { id in
        built.append(id)
        return Text("\(id)").sizing(y: .fixed(10))
      }, context: context)
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(Set(built) == Set(0..<4))
    #expect(context.interaction.scrollStates.values.first?.limit.y == 3840)
    #expect(scene.paint().commands.first == .pushClip(rect))
  }

  @Test func streamingTextChangesMeasuredExtentWithoutLosingAnchor() throws {
    let scene = NodeScene()
    let context = BlockContext()
    let snapshot = VirtualListSnapshot(ids: 0..<100)
    let controller = ScrollViewController()
    var message = "short"
    func content() -> VariableHeightList {
      VariableHeightList(snapshot: snapshot, estimatedHeight: 20, controller: controller) { id in
        Text(id == 0 ? message : "Row \(id)").wrapping()
      }
    }
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(content(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let oldLimit = context.interaction.scrollStates.values.first!.limit.y
    message = String(repeating: "streaming text ", count: 20)
    try scene.update(content(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(context.interaction.scrollStates.values.first!.limit.y > oldLimit)
    #expect(controller.offset == 0)
  }

  @Test func widthChangesPreserveItemAndOffsetAfterMeasuredHeightReset() throws {
    let scene = NodeScene()
    let context = BlockContext()
    let controller = ScrollViewController()
    let snapshot = VirtualListSnapshot(ids: 0..<100)
    let list = VariableHeightList(snapshot: snapshot, estimatedHeight: 20, overscan: 0, controller: controller) { id in
      Text("\(id)").sizing(y: .fixed(40))
    }
    var rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(list, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -45)))
    rect.size.width = 200
    try scene.layout(in: rect)
    #expect(controller.offset == 25)
  }

  @Test func logicalSelectionSurvivesScrollingAndReordering() throws {
    let scene = NodeScene()
    let context = BlockContext()
    let controller = ScrollViewController()
    let selection = ScrollSelection(50)
    var actions: [Int] = []
    func content(_ ids: [Int]) -> VariableHeightList {
      VariableHeightList(
        snapshot: VirtualListSnapshot(ids: ids), estimatedHeight: 20, overscan: 0,
        controller: controller, selection: selection
      ) { id in Button("\(id)") { actions.append(id) }.sizing(y: .fixed(20)) }
    }
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(content(Array(0..<100)), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(selection.selectedID == 50)
    controller.scrollToRow(50)
    try scene.update(content(Array(0..<100)), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(context.interaction.selectedLeafID != nil)
    try scene.dispatch(InputState(commands: [.action(.activate)]))
    #expect(actions == [50])
    controller.scrollToTop()
    try scene.update(content(Array(0..<100)), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(selection.selectedID == 50)
    #expect(context.interaction.selectedLeafID == nil)
    try scene.update(content(Array((0..<100).reversed())), context: context)
    try scene.layout(in: rect)
    #expect(selection.selectedID == 50)
    try scene.update(content([1, 2, 3]), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let registration = context.interaction.logicalSelections.values.first!
    #expect(registration.selectedKey()?.value as? Int == 1)
  }

  @Test func insertionAndDeletionRestoreItemAnchorWithoutBuildingHistory() throws {
    let scene = NodeScene()
    let context = BlockContext()
    let controller = ScrollViewController()
    var built: [Int] = []
    func content(_ ids: [Int]) -> VariableHeightList {
      VariableHeightList(
        snapshot: VirtualListSnapshot(ids: ids), estimatedHeight: 20, overscan: 0, controller: controller
      ) { id in
        built.append(id)
        return Text("\(id)").sizing(y: .fixed(20))
      }
    }
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(content(Array(0..<100)), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    controller.scrollToRow(50)
    try scene.update(content(Array(0..<100)), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(controller.offset == 1000)
    try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -5)))
    try scene.update(content([-1] + Array(0..<100)), context: context)
    try scene.layout(in: rect)
    #expect(controller.offset == 1025)
    #expect(built.suffix(3) == [50, 51, 52])
    try scene.update(content(Array(0..<50) + Array(51..<100)), context: context)
    try scene.layout(in: rect)
    #expect(controller.offset == 1025)
  }

  @Test func bottomFollowingIsConditionalOnPreviousPosition() throws {
    let scene = NodeScene()
    let context = BlockContext()
    let controller = ScrollViewController()
    func content(_ count: Int) -> VariableHeightList {
      VariableHeightList(
        snapshot: VirtualListSnapshot(ids: 0..<count), estimatedHeight: 20, overscan: 0,
        controller: controller, sticksToBottom: true
      ) { id in Text("\(id)").sizing(y: .fixed(20)) }
    }
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(content(10), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(controller.offset == 160)
    try scene.update(content(11), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(controller.offset == 180)
    try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: 20)))
    try scene.update(content(12), context: context)
    try scene.layout(in: rect)
    #expect(controller.offset == 160)
  }

  @Test func emptyAndShrinkingContentClampScrollBeforePlacement() throws {
    let scene = NodeScene()
    let context = BlockContext()
    var height: Float = 40
    let snapshot = VirtualListSnapshot(ids: 0..<10)
    func content() -> VariableHeightList {
      VariableHeightList(snapshot: snapshot, estimatedHeight: 40, overscan: 0) { id in
        Text("\(id)").sizing(y: .fixed(height))
      }
    }
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(content(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -1000)))
    height = 10
    try scene.update(content(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let state = context.interaction.scrollStates.values.first!
    #expect(state.offset.y <= state.limit.y)
    #expect(context.interaction.tree?.hitTest(Point(x: 10, y: 10)) != nil)
    try scene.update(
      VariableHeightList(snapshot: VirtualListSnapshot(ids: [Int]()), estimatedHeight: 20) { _ in Text("unused") },
      context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(context.interaction.scrollStates.values.first?.offset.y == 0)
    #expect(scene.liveCount == 1)
  }

  @Test func changedHeightsAboveViewportPreserveOffsetWithinAnchor() throws {
    let snapshot = VirtualListSnapshot(ids: 0..<100)
    let context = BlockContext()
    let scene = NodeScene()
    var firstHeight: Float = 20
    func content() -> VariableHeightList {
      VariableHeightList(snapshot: snapshot, estimatedHeight: 20, overscan: 1) { id in
        Text("\(id)").sizing(y: .fixed(id == 0 ? firstHeight : 20))
      }
    }
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(content(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -25)))
    firstHeight = 40
    try scene.update(content(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(context.interaction.scrollStates.values.first?.offset.y == 45)
    #expect(context.interaction.scrollStates.values.first?.limit.y == 1980)
  }
}
