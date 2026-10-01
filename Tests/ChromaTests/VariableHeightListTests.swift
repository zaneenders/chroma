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
