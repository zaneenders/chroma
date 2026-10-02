import Testing

@testable import Chroma

@MainActor
struct NodeTextSelectionTests {
  private let viewport = Size(width: 80, height: 80)

  @Test func selectablePaintMatchesLegacyWithoutRegisteringDuringPaint() throws {
    for wraps in [false, true] {
      let context = BlockContext()
      let text = Text("café\n👨‍👩‍👧‍👦 abcdefghijklmnop").wrapping(wraps).selectable()
      let scene = NodeScene()
      let rect = Rect(origin: .zero, size: viewport)
      try scene.update(text, context: context)
      try scene.layout(in: rect)
      scene.prepare(viewport: viewport)
      for selected in [false, true] {
        if selected {
          try scene.dispatch(InputState(commands: [.navigation(.nextFocus), .action(.activate)]))
          try scene.dispatch(InputState(textEvents: [.selectAll]))
        }
        let tree = context.interaction.tree
        let builds = scene.textLayoutBuilds
        let actual = scene.paint(cullingEnabled: false)
        #expect(context.interaction.tree === tree)
        #expect(scene.textLayoutBuilds == builds)
        context.interaction.beginFrame(input: InputState(), processingInput: false)
        var expected = DrawList()
        BlockEngine.draw(text, into: &expected, in: rect, context: context)
        context.interaction.endFrame()
        #expect(actual.commands == expected.commands)
      }
    }
  }

  @Test func readOnlySelectionCopiesUnicodeAndReusesLayoutAcrossOrderedInput() throws {
    let context = BlockContext()
    let producer = NodeFrameProducer()
    let text = Text("café\n👨‍👩‍👧‍👦 tea").selectable()
    try producer.refresh(content: text, viewport: viewport, context: context, onChange: {})
    try producer.dispatch(InputState(commands: [.navigation(.nextFocus)]), onChange: {})
    try producer.dispatch(InputState(commands: [.action(.activate)]), onChange: {})
    let layouts = producer.layouts
    let builds = producer.textLayoutBuilds
    for _ in 0..<8 {
      try producer.dispatch(InputState(textEvents: [.selectCaretRight]), onChange: {})
    }
    #expect(context.interaction.copyText() == "café\n👨‍👩‍👧‍👦 t")
    #expect(producer.layouts == layouts)
    #expect(producer.textLayoutBuilds == builds)
    #expect(producer.paints == 0)
    try producer.dispatch(InputState(textEvents: [.insert("replacement")]), onChange: {})
    try producer.dispatch(InputState(textEvents: [.selectAll]), onChange: {})
    #expect(context.interaction.copyText() == text.content)
    _ = producer.paint()
    #expect(producer.textLayoutBuilds == builds)
  }

  private final class Clock { var now = 100.0 }

  @Test func readOnlyCaretBlinksWithoutLayoutAndStopsImmediatelyWithSelection() throws {
    let clock = Clock()
    let context = BlockContext()
    let producer = NodeFrameProducer(clock: { clock.now })
    try producer.refresh(content: Text("abc").selectable(), viewport: viewport, context: context, onChange: {})
    try producer.dispatch(InputState(commands: [.navigation(.nextFocus)]), onChange: {})
    try producer.dispatch(InputState(commands: [.action(.activate)]), onChange: {})
    let visible = producer.paint()
    #expect(producer.needsAnimationFrame)
    let builds = producer.textLayoutBuilds
    clock.now = 100.8
    #expect(producer.renderAnimations().commands != visible.commands)
    #expect(producer.textLayoutBuilds == builds)
    try producer.dispatch(InputState(textEvents: [.selectAll]), onChange: {})
    #expect(!producer.needsAnimationFrame)
    _ = producer.paint()
    #expect(!producer.needsAnimationFrame)
  }

  @Test func pointerDragUsesRetainedUnicodeLayoutBeforeFirstPaint() throws {
    let context = BlockContext()
    let scene = NodeScene()
    let rect = Rect(origin: .zero, size: viewport)
    try scene.update(Text("café 👨‍👩‍👧‍👦 tea").selectable(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: viewport)
    let cell = context.fontMetrics.cellAdvance
    let builds = scene.textLayoutBuilds
    try scene.dispatch(InputState(pointerPosition: Point(x: 0, y: 2), pointerDown: true, pointerPressed: true))
    try scene.dispatch(InputState(pointerPosition: Point(x: cell * 6, y: 2), pointerDown: true))
    try scene.dispatch(InputState(pointerPosition: Point(x: cell * 6, y: 2), pointerReleased: true))
    #expect(context.interaction.copyText() == "café 👨‍👩‍👧‍👦")
    #expect(scene.textLayoutBuilds == builds)
    #expect(scene.paintVisits == 0)
  }

  @Test func removingSelectableTextClearsSelectionAndRetainedRegistry() throws {
    let context = BlockContext()
    let scene = NodeScene()
    let rect = Rect(origin: .zero, size: viewport)
    try scene.update(Text("abc").selectable(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: viewport)
    try scene.dispatch(InputState(commands: [.navigation(.nextFocus), .action(.activate)]))
    try scene.dispatch(InputState(textEvents: [.selectAll]))
    #expect(context.interaction.copyText() == "abc")
    try scene.update(EmptyBlock(), context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: viewport)
    #expect(context.interaction.editingLeaf == nil)
    #expect(context.interaction.copyText() == nil)
  }
}
