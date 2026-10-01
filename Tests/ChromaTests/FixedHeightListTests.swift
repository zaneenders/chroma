import Testing

@testable import Chroma

@MainActor
struct FixedHeightListTests {
  @Test func visibleRangesAreBoundedAndIncludeOnlyRequestedOverscan() {
    let list = FixedHeightList(count: 1_000_000, rowHeight: 20) { Text("\($0)") }
    #expect(list.visibleRange(offset: 0, height: 40) == 0..<3)
    #expect(list.visibleRange(offset: 1_000_005, height: 40) == 49_999..<50_004)
    #expect(list.visibleRange(offset: 19_999_960, height: 40) == 999_997..<1_000_000)
    #expect(list.visibleRange(offset: 0, height: 0).isEmpty)
  }

  @Test func scrollingBuildsOnlyViewportRowsAndRefreshesHitRegionsBeforePaint() throws {
    let scene = NodeScene()
    let context = BlockContext()
    var built: [Int] = []
    var actions: [Int] = []
    let list = FixedHeightList(count: 1_000_000, rowHeight: 20, overscan: 0) { index in
      built.append(index)
      return Button("Row \(index)") { actions.append(index) }
    }
    let rect = Rect(x: 10, y: 10, width: 100, height: 40)
    try scene.update(list, context: context)
    #expect(built.isEmpty)
    try scene.layout(in: rect)
    scene.prepare(viewport: Size(width: 200, height: 100))
    #expect(built == [0, 1])
    let point = Point(x: 20, y: 20)
    try scene.dispatch(InputState(pointerPosition: point, scrollDelta: Point(x: 0, y: -1_000_000)))
    #expect(built == [0, 1, 50_000, 50_001])
    try scene.dispatch(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    try scene.dispatch(InputState(pointerPosition: point, pointerReleased: true))
    #expect(actions == [50_000])
    let commands = scene.paint().commands
    #expect(commands.first == .pushClip(rect))
    #expect(commands.last == .popClip)
    #expect(built.count == 4)
    #expect(context.interaction.tree?.hitTest(Point(x: 20, y: 5)) == nil)
  }

  @Test func orderedSmallScrollDeltasReuseRowsAndOutsideScrollIsIgnored() throws {
    let scene = NodeScene()
    let context = BlockContext()
    var built: [Int] = []
    let list = FixedHeightList(count: 100, rowHeight: 20) { index in
      built.append(index)
      return Text("\(index)")
    }
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(list, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    for _ in 0..<8 {
      try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -1)))
    }
    #expect(context.interaction.scrollStates.values.first?.offset.y == 8)
    #expect(built == [0, 1, 2, 0, 1, 2, 3])
    try scene.dispatch(InputState(pointerPosition: Point(x: 110, y: 10), scrollDelta: Point(x: 0, y: -50)))
    #expect(context.interaction.scrollStates.values.first?.offset.y == 8)
    #expect(built.count == 7)
  }

  @Test func replacementAndResizeRefreshVisibleRowsWithoutPainting() throws {
    let scene = NodeScene()
    let context = BlockContext()
    var built: [String] = []
    var actions: [String] = []
    func content(_ revision: String) -> FixedHeightList {
      FixedHeightList(count: 100, rowHeight: 20, overscan: 0) { index in
        let label = "\(revision)-\(index)"
        built.append(label)
        return Button(label) { actions.append(label) }
      }
    }
    let small = Rect(x: 0, y: 0, width: 100, height: 20)
    try scene.update(content("old"), context: context)
    try scene.layout(in: small)
    scene.prepare(viewport: small.size)
    try scene.update(content("new"), context: context)
    let large = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.layout(in: large)
    scene.prepare(viewport: large.size)
    let point = Point(x: 10, y: 30)
    try scene.dispatch(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    try scene.dispatch(InputState(pointerPosition: point, pointerReleased: true))
    #expect(built == ["old-0", "new-0", "new-1"])
    #expect(actions == ["new-1"])
  }

  @Test func snapshotsIndexReorderedAndRemovedIDs() {
    let original = VirtualListSnapshot(ids: ["a", "b", "c"], revision: 1)
    let replacement = VirtualListSnapshot(ids: ["c", "a"], revision: 2)
    #expect(original.index(of: "b") == 1)
    #expect(replacement.index(of: "c") == 0)
    #expect(replacement.index(of: "b") == nil)
    #expect(replacement.revision == 2)
    #expect(original.ids == ["a", "b", "c"])
  }

  @Test func snapshotRowsAreDeferredAndWarmWorkIsViewportBounded() throws {
    for count in [1_000, 100_000, 1_000_000] {
      var visited = 0
      let ids = (0..<count).lazy.map { index in
        visited += 1
        return index
      }
      let snapshot = VirtualListSnapshot(ids: ids)
      #expect(visited == count)
      let scene = NodeScene()
      let context = BlockContext()
      var built: [Int] = []
      let list = FixedHeightList(snapshot: snapshot, rowHeight: 20, overscan: 0) { id in
        built.append(id)
        return Text("\(id)")
      }
      let rect = Rect(x: 0, y: 0, width: 100, height: 40)
      try scene.update(list, context: context)
      #expect(built.isEmpty)
      try scene.layout(in: rect)
      scene.prepare(viewport: rect.size)
      let offset = Float((count - 2) * 20)
      try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -offset)))
      #expect(built == [0, 1, count - 2, count - 1])
      let layouts = scene.layouts
      for _ in 0..<8 {
        try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10)))
        _ = try scene.layout(in: rect)
        _ = scene.paint()
      }
      #expect(scene.layouts == layouts)
      #expect(built.count == 4)
      #expect(visited == count)
      #expect(scene.liveCount == 3)
    }
  }

  @Test func snapshotReplacementRoutesFreshCallbacksByID() throws {
    let scene = NodeScene()
    let context = BlockContext()
    var actions: [String] = []
    func list(_ ids: [String], revision: UInt64) -> FixedHeightList {
      FixedHeightList(snapshot: VirtualListSnapshot(ids: ids, revision: revision), rowHeight: 20, overscan: 0) { id in
        Button(id) { actions.append("\(revision)-\(id)") }
      }
    }
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(list(["a", "b", "c"], revision: 1), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.update(list(["b", "a"], revision: 2), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let point = Point(x: 10, y: 10)
    try scene.dispatch(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    try scene.dispatch(InputState(pointerPosition: point, pointerReleased: true))
    #expect(actions == ["2-b"])
  }

  @Test func emptyListAndScrollPastEndStayBounded() throws {
    for count in [0, 2] {
      let scene = NodeScene()
      let context = BlockContext()
      var built: [Int] = []
      try scene.update(
        FixedHeightList(count: count, rowHeight: 20, overscan: 0) { index in
          built.append(index)
          return Text("\(index)")
        }, context: context)
      let rect = Rect(x: 0, y: 0, width: 100, height: 20)
      try scene.layout(in: rect)
      scene.prepare(viewport: rect.size)
      try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -1000)))
      #expect(context.interaction.scrollStates.values.first?.offset.y == Float(max(0, count - 1) * 20))
      #expect(built == (count == 0 ? [] : [0, 1]))
    }
  }
}
