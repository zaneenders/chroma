import Testing

@testable import Chroma

@MainActor
struct VirtualRowRetentionTests {
  @Test func scopedCommandsFollowVirtualRowsAndOutsideFocusIsNotStolen() throws {
    let scene = NodeScene()
    let context = BlockContext()
    let selection = ScrollSelection(0)
    var routed: [Int] = []
    let list = VariableHeightList(
      snapshot: VirtualListSnapshot(ids: 0..<100), estimatedHeight: 40, selection: selection
    ) { id in
      Button("Row") {}.sizing(y: .fixed(40)).onCommand(.application("row")) {
        routed.append(id)
        return .handled
      }
    }
    let content = HStack {
      list
      Button("Outside") {}
    }
    let rect = Rect(x: 0, y: 0, width: 400, height: 80)
    try scene.update(content, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let navigation = context.interaction.navigation!
    let row = navigation.children[0].children[0].id!
    let outside = navigation.children[1].id!
    context.interaction.focus(row)
    try scene.dispatch(InputState(commands: [.application("row")]))
    #expect(routed == [0])
    context.interaction.focus(outside)
    scene.prepare(viewport: rect.size)
    #expect(context.interaction.selectedLeafID == outside)
    try scene.dispatch(InputState(commands: [.application("row")]))
    #expect(routed == [0])
  }

  @Test func multiControlSelectionAndScopeRestore() throws {
    let scene = NodeScene()
    let context = BlockContext()
    let selection = ScrollSelection(0)
    var actions: [String] = []
    let list = VariableHeightList(
      snapshot: VirtualListSnapshot(ids: 0..<100), estimatedHeight: 40, selection: selection
    ) { id in
      HStack {
        Button("A") { actions.append("A\(id)") }
        Button("B") { actions.append("B\(id)") }
      }.sizing(y: .fixed(40))
    }
    let rect = Rect(x: 0, y: 0, width: 200, height: 80)
    try scene.update(list, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let leaves = context.interaction.navigation!.children[0].children
    let second = leaves[1].id!
    context.interaction.focus(second)
    scene.prepare(viewport: rect.size)
    #expect(context.interaction.selectedLeafID == second)
    try scene.dispatch(InputState(commands: [.action(.activate)]))
    #expect(actions == ["B0"])
    try scene.dispatch(InputState(commands: [.navigation(.stepOut)]))
    try scene.dispatch(InputState(commands: [.navigation(.stepIn)]))
    #expect(context.interaction.selectedLeafID == second)
    try scene.dispatch(InputState(commands: [.navigation(.down)]))
    #expect(selection.selectedID == 1)
  }

  @Test func editingAndCaptureSurviveFarScrollAndReleaseOnRemoval() throws {
    for variable in [false, true] {
      let scene = NodeScene()
      let context = BlockContext()
      var text = "hello"
      let snapshot = VirtualListSnapshot(ids: 0..<1000)
      let row: @MainActor (Int) -> any Block = { _ in
        TextEditor(singleLine: true, text: { text }, onChange: { text = $0 }).sizing(y: .fixed(40))
      }
      let content: any Block =
        variable
        ? VariableHeightList(snapshot: snapshot, estimatedHeight: 40, overscan: 0, row: row)
        : FixedHeightList(snapshot: snapshot, rowHeight: 40, overscan: 0, row: row)
      let rect = Rect(x: 0, y: 0, width: 200, height: 40)
      try scene.update(content, context: context)
      try scene.layout(in: rect)
      scene.prepare(viewport: rect.size)
      try scene.dispatch(InputState(commands: [.navigation(.nextFocus), .action(.activate)]))
      let editing = context.interaction.editingLeaf
      #expect(editing != nil)
      try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -20000)))
      #expect(context.interaction.editingLeaf == editing)
      #expect(scene.liveCount < 10)
      try scene.dispatch(InputState(textEvents: [.insert("!")]))
      #expect(text.contains("!"))
      try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: 20000)))
      #expect(context.interaction.editingLeaf == editing)
      #expect(context.interaction.tree?.findLeaf(editing!) != nil)
      try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), pointerDown: true, pointerPressed: true))
      let pressed = context.interaction.pressedLeaf
      try scene.dispatch(
        InputState(pointerPosition: Point(x: 10, y: 100), pointerDown: true, scrollDelta: Point(x: 0, y: -1000)))
      #expect(context.interaction.pressedLeaf == pressed)
      try scene.dispatch(InputState(pointerPosition: Point(x: 10, y: 100), pointerReleased: true))
      #expect(context.interaction.pressedLeaf == nil)
      try scene.update(EmptyBlock(), context: context)
      try scene.layout(in: rect)
      scene.prepare(viewport: rect.size)
      #expect(context.interaction.editingLeaf == nil)
      #expect(scene.liveCount == 1)
    }
  }
}
