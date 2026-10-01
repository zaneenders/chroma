import Testing

@testable import Chroma

@MainActor
struct NodeSceneTests {
  private let rect = Rect(x: 0, y: 0, width: 120, height: 40)

  @Test func buttonPaintMatchesExistingOutputWithoutRegisteringOrExecutingActions() throws {
    let context = BlockContext()
    var actions = 0
    let button = Button("Run") { actions += 1 }
    let scene = NodeScene()
    try scene.update(button, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let tree = context.interaction.tree
    let expected = scene.paint()
    #expect(context.interaction.tree === tree)
    #expect(context.interaction.builderStack.isEmpty)
    #expect(actions == 0)
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    var legacy = DrawList()
    BlockEngine.draw(button, into: &legacy, in: rect, context: context)
    context.interaction.endFrame()
    #expect(expected.commands == legacy.commands)
  }

  private final class Counter {
    var builds = 0
    var actions: [Int] = []
  }

  private struct Content: Block {
    let counter: Counter
    var body: some Block {
      counter.builds += 1
      return Button("Run") { counter.actions.append(counter.actions.count) }
    }
  }

  @Test func eightOrderedActivationsReusePreparedContentWithoutPainting() throws {
    let scene = NodeScene()
    let counter = Counter()
    try scene.update(Content(counter: counter), context: BlockContext())
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.dispatch(InputState(commands: [.navigation(.nextFocus)]))
    for _ in 0..<8 { try scene.dispatch(InputState(commands: [.action(.activate)])) }
    #expect(counter.actions == Array(0..<8))
    #expect(counter.builds == 1)
    #expect(!scene.paint().commands.isEmpty)
    #expect(counter.builds == 1)
  }

  @Test func replacementRefreshesCallbacksAndResizeRefreshesHitGeometryWithoutPaint() throws {
    let scene = NodeScene()
    let context = BlockContext()
    var actions: [String] = []
    try scene.update(Button("Old") { actions.append("old") }.id("button"), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.update(Button("New") { actions.append("new") }.id("button"), context: context)
    let moved = Rect(x: 200, y: 0, width: 120, height: 40)
    try scene.layout(in: moved)
    scene.prepare(viewport: Size(width: 400, height: 100))
    try scene.dispatch(InputState(commands: [.navigation(.nextFocus)]))
    try scene.dispatch(InputState(commands: [.action(.activate)]))
    let point = Point(x: 210, y: 10)
    try scene.dispatch(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    try scene.dispatch(InputState(pointerPosition: point, pointerReleased: true))
    #expect(actions == ["new", "new"])
    #expect(context.interaction.tree?.hitTest(Point(x: 10, y: 10)) == nil)
  }

  @Test func replacingButtonWithTextRemovesItsActionBeforeTheNextEvent() throws {
    let scene = NodeScene()
    let context = BlockContext()
    var actions = 0
    try scene.update(Button("Run") { actions += 1 }.id("content"), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.dispatch(InputState(commands: [.navigation(.nextFocus)]))
    try scene.dispatch(InputState(commands: [.action(.activate)]))
    try scene.update(Text("Removed").id("content"), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.dispatch(InputState(commands: [.navigation(.nextFocus)]))
    try scene.dispatch(InputState(commands: [.action(.activate)]))
    #expect(actions == 1)
    #expect(context.interaction.registrations.buttonActions.isEmpty)
  }

  @Test func unsupportedContentDoesNotReplaceTheCommittedScene() throws {
    let scene = NodeScene()
    try scene.update(Text("Retained"), context: BlockContext())
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let before = scene.paint().commands
    do {
      try scene.update(Text("Selectable").selectable(), context: BlockContext())
      Issue.record("Selectable text must not silently lose its interaction behavior")
    } catch NodeScene.BuildError.unsupportedBlock {}
    #expect(scene.paint().commands == before)
  }

  @Test func nestedAndReversedStacksMatchLegacyMeasurementPaintAndFocusGeometry() throws {
    for reversed in [false, true] {
      let context = BlockContext()
      var stack = VStack(spacing: 3) {
        HStack(spacing: 5, alignment: .bottom) {
          Text("Short")
          Button("Tall") {}
        }
        Text("Second")
        EmptyBlock()
      }
      if reversed { stack = stack.reverseLayout() }
      let scene = NodeScene()
      try scene.update(stack, context: context)
      let measured = try scene.layout(in: rect)
      #expect(measured == BlockEngine.measure(stack, proposal: rect.size, context: context))
      scene.prepare(viewport: rect.size)
      let result = scene.paint()
      let tree = try #require(context.interaction.tree)
      let firstRow = tree.children[0].children[0]
      let short = firstRow.children[0]
      let tall = firstRow.children[1]
      #expect(short.rect.maxY == tall.rect.maxY)
      context.interaction.beginFrame(input: context.interaction.input, processingInput: false)
      var legacy = DrawList()
      BlockEngine.draw(stack, into: &legacy, in: rect, context: context)
      context.interaction.endFrame()
      #expect(result.commands == legacy.commands)
    }
  }

  @Test func keyedStackReorderingPreservesFocusedControlAndRefreshesActions() throws {
    let context = BlockContext()
    let scene = NodeScene()
    var actions: [String] = []
    func content(_ ids: [Int], revision: String) -> VStack {
      VStack(spacing: 2) {
        ForEach(ids, id: \.self) { id in
          Button("Row \(id)") { actions.append("\(revision)-\(id)") }
        }
      }
    }
    try scene.update(content([1, 2], revision: "old"), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let point = Point(x: 10, y: 10)
    try scene.dispatch(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    try scene.dispatch(InputState(pointerPosition: point, pointerReleased: true))
    let selected = context.interaction.selectedLeafID
    try scene.update(content([2, 1], revision: "new"), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    #expect(context.interaction.selectedLeafID == selected)
    try scene.dispatch(InputState(commands: [.action(.activate)]))
    #expect(actions == ["old-1", "new-1"])
  }

  @Test func unsupportedNestedChildLeavesCommittedSceneUnchanged() throws {
    let scene = NodeScene()
    let context = BlockContext()
    try scene.update(VStack { Text("Retained") }, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let before = scene.paint().commands
    do {
      try scene.update(
        VStack {
          Text("New")
          Text("Unsupported").selectable()
        }, context: context)
      Issue.record("Unsupported nested content must fail atomically")
    } catch NodeScene.BuildError.unsupportedBlock {}
    #expect(scene.paint().commands == before)
  }

  @Test func wrappedTextPaintUsesRetainedLines() throws {
    let context = BlockContext()
    let text = Text("one two three").wrapping()
    let scene = NodeScene()
    try scene.update(text, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let result = scene.paint()
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    var legacy = DrawList()
    BlockEngine.draw(text, into: &legacy, in: rect, context: context)
    context.interaction.endFrame()
    #expect(result.commands == legacy.commands)
  }
}
