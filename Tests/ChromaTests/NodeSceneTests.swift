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
    scene.layout(in: rect)
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
    scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    scene.dispatch(InputState(commands: [.navigation(.nextFocus)]))
    for _ in 0..<8 { scene.dispatch(InputState(commands: [.action(.activate)])) }
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
    scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    try scene.update(Button("New") { actions.append("new") }.id("button"), context: context)
    let moved = Rect(x: 200, y: 0, width: 120, height: 40)
    scene.layout(in: moved)
    scene.prepare(viewport: Size(width: 400, height: 100))
    scene.dispatch(InputState(commands: [.navigation(.nextFocus)]))
    scene.dispatch(InputState(commands: [.action(.activate)]))
    let point = Point(x: 210, y: 10)
    scene.dispatch(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    scene.dispatch(InputState(pointerPosition: point, pointerReleased: true))
    #expect(actions == ["new", "new"])
    #expect(context.interaction.tree?.hitTest(Point(x: 10, y: 10)) == nil)
  }

  @Test func replacingButtonWithTextRemovesItsActionBeforeTheNextEvent() throws {
    let scene = NodeScene()
    let context = BlockContext()
    var actions = 0
    try scene.update(Button("Run") { actions += 1 }.id("content"), context: context)
    scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    scene.dispatch(InputState(commands: [.navigation(.nextFocus)]))
    scene.dispatch(InputState(commands: [.action(.activate)]))
    try scene.update(Text("Removed").id("content"), context: context)
    scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    scene.dispatch(InputState(commands: [.navigation(.nextFocus)]))
    scene.dispatch(InputState(commands: [.action(.activate)]))
    #expect(actions == 1)
    #expect(context.interaction.registrations.buttonActions.isEmpty)
  }

  @Test func unsupportedContentDoesNotReplaceTheCommittedScene() throws {
    let scene = NodeScene()
    try scene.update(Text("Retained"), context: BlockContext())
    scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let before = scene.paint().commands
    do {
      try scene.update(Text("Selectable").selectable(), context: BlockContext())
      Issue.record("Selectable text must not silently lose its interaction behavior")
    } catch NodeScene.BuildError.unsupportedBlock {}
    #expect(scene.paint().commands == before)
  }

  @Test func wrappedTextPaintUsesRetainedLines() throws {
    let context = BlockContext()
    let text = Text("one two three").wrapping()
    let scene = NodeScene()
    try scene.update(text, context: context)
    scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let result = scene.paint()
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    var legacy = DrawList()
    BlockEngine.draw(text, into: &legacy, in: rect, context: context)
    context.interaction.endFrame()
    #expect(result.commands == legacy.commands)
  }
}
