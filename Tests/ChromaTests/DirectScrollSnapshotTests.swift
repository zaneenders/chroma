import Testing

@testable import Chroma

@MainActor
struct DirectScrollSnapshotTests {
  @MainActor private final class SnapshotState {
    var color = Color.white
    var builds = 0
    var measurements = 0
    var registrations = 0
  }

  @Test(arguments: [false, true])
  func rowHighlightsStayImmediatelyAfterTheirContent(variableRows: Bool) throws {
    let context = LayoutContext()
    let controller = ScrollViewController()
    let viewport = Rect(x: 10, y: 20, width: 100, height: 30)
    var rowIDs: [Int: WidgetID] = [:]
    var controlID: WidgetID?
    let buildRow: ScrollView.RowBuilder<Int> = { buffer, context, index in
      rowIDs[index] = context.widgetID
      let control = context.keyed("control")
      if index == 1 { controlID = control.widgetID }
      return buffer.customLeaf(
        context: context, focusRule: index == 1 ? .control : .standard,
        measure: { Size(width: $0.width, height: 10) },
        register: { rect in
          if index == 1 { control.registerFocusable(in: rect, action: {}) }
        },
        paint: { list, rect in
          list.fillRect(rect, color: index == 1 ? .black : .white)
          if index == 1 { control.paintFocusHighlight(in: rect, into: &list) }
        })
    }
    let view: ScrollView
    if variableRows {
      view = ScrollView(
        showsIndicator: false, controller: controller,
        rows: (0..<3).map { index in
          ScrollView.Row(id: index) { buffer, context in buildRow(&buffer, context, index) }
        })
    } else {
      view = ScrollView(
        data: 0..<3, rowHeight: 10, showsIndicator: false, controller: controller, build: buildRow)
    }
    var buffer = LayoutBuffer()
    let root = buffer.scrollView(view, context: context)
    beginTestFrame(context.interaction, input: InputState(pointerPosition: Point(x: -10, y: -10)))
    buffer.register(root, in: viewport)
    context.interaction.endFrame()

    let state = try #require(context.interaction.scrollStates.values.first)
    let firstID = try #require(rowIDs[0])
    let middleID = try #require(controlID)
    let lastID = try #require(rowIDs[2])
    #expect(Set(state.rows.keys) == [firstID, middleID, lastID])
    #expect(state.rowKeys[firstID] == StructuralKey(0))
    #expect(state.rowKeys[middleID] == StructuralKey(1))
    #expect(state.rowKeys[lastID] == StructuralKey(2))

    for (selected, selectedIndex) in [(firstID, 0), (middleID, 1), (lastID, 2)] {
      context.interaction.selectedLeafID = selected
      var actual = DrawList()
      buffer.paint(root, into: &actual, in: viewport)
      var expected = DrawList()
      expected.pushClip(viewport)
      for index in 0..<3 {
        let rect = Rect(x: 10, y: 20 + Float(index * 10), width: 100, height: 10)
        expected.fillRect(rect, color: index == 1 ? .black : .white)
        if index == selectedIndex { expected.strokeRect(rect, width: 2, color: context.theme.focus.ring) }
      }
      expected.popClip()
      #expect(actual.commands == expected.commands)
    }
  }

  @Test(arguments: ["ordinary", "uniform", "variable"])
  func laterRegistrationCannotReplaceAnEarlierPaintSnapshot(kind: String) {
    var context = LayoutContext()
    context.navigationIgnored = true
    let controller = ScrollViewController()
    let viewport = Rect(x: 10, y: 20, width: 100, height: 20)
    let state = SnapshotState()
    let build: LayoutBuilder = { buffer, context in
      state.builds += 1
      let color = state.color
      let size = kind == "ordinary" ? Size(width: 200, height: 1000) : Size(width: 100, height: 10)
      return buffer.customLeaf(
        context: context,
        measure: { _ in
          state.measurements += 1
          return size
        },
        register: { _ in state.registrations += 1 },
        paint: { list, rect in list.fillRect(rect, color: color) })
    }
    let view: ScrollView
    switch kind {
    case "ordinary":
      view = ScrollView(controller: controller, build: build)
    case "uniform":
      view = ScrollView(
        data: 0..<100, rowHeight: 10, controller: controller,
        build: { buffer, context, _ in build(&buffer, context) })
    default:
      view = ScrollView(controller: controller, rows: (0..<100).map { ScrollView.Row(id: $0, build: build) })
    }
    func register(in buffer: inout LayoutBuffer) -> LayoutNode {
      let root = buffer.scrollView(view, context: context)
      beginTestFrame(context.interaction, input: InputState())
      buffer.register(root, in: viewport)
      context.interaction.endFrame()
      return root
    }

    var firstBuffer = LayoutBuffer()
    let first = register(in: &firstBuffer)
    var original = DrawList()
    firstBuffer.paint(first, into: &original, in: viewport)

    state.color = .black
    controller.scroll(to: 50)
    var nextBuffer = LayoutBuffer()
    let next = register(in: &nextBuffer)
    var current = DrawList()
    nextBuffer.paint(next, into: &current, in: viewport)
    #expect(controller.offset == 50)
    #expect(current.commands != original.commands)
    let preparedBuilds = state.builds
    let preparedMeasurements = state.measurements
    let preparedRegistrations = state.registrations
    controller.scrollToBottom()

    var repeated = DrawList()
    firstBuffer.paint(first, into: &repeated, in: viewport)
    #expect(repeated.commands == original.commands)
    #expect(state.builds == preparedBuilds)
    #expect(state.measurements == preparedMeasurements)
    #expect(state.registrations == preparedRegistrations)
    #expect(controller.offset == 50)
    #expect(controller.request == .bottom)
  }
}
