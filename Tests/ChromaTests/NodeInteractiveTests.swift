import Observation
import Testing

@testable import Chroma

@MainActor
struct NodeInteractiveTests {
  private final class Counts {
    var builds = 0
    var actions = 0
  }
  @Observable final class Model { var label = "Initial" }

  @Test func phaseChangesRefreshBeforePaintAndUnchangedEventsReuseContent() throws {
    let counts = Counts()
    let context = BlockContext()
    let producer = NodeFrameProducer()
    let control = Interactive(action: { counts.actions += 1 }) { phase in
      counts.builds += 1
      return Text(phase == .pressed ? "Pressed" : phase == .hovered ? "Hovered" : "Idle")
    }
    let viewport = Size(width: 100, height: 40)
    try producer.refresh(content: control, viewport: viewport, context: context, onChange: {})
    try producer.dispatch(InputState(pointerPosition: Point(x: 10, y: 10)), onChange: {})
    let hoveredBuilds = counts.builds
    for _ in 0..<8 {
      try producer.dispatch(InputState(pointerPosition: Point(x: 10, y: 10)), onChange: {})
    }
    #expect(counts.builds == hoveredBuilds)
    #expect(producer.paints == 0)
    try producer.dispatch(
      InputState(pointerPosition: Point(x: 10, y: 10), pointerDown: true, pointerPressed: true), onChange: {})
    let beforePaint = counts.builds
    let frame = producer.paint()
    #expect(counts.builds == beforePaint)
    #expect(frame.commands.contains { if case .text(_, "Pressed", _, _) = $0 { true } else { false } })
    try producer.dispatch(InputState(pointerPosition: Point(x: 10, y: 10), pointerReleased: true), onChange: {})
    #expect(counts.actions == 1)
    let builds = counts.builds
    _ = producer.paint()
    #expect(counts.builds == builds)
  }

  @Test func phaseContentRemainsObservedWithoutRootRebuild() throws {
    let model = Model()
    let context = BlockContext()
    let producer = NodeFrameProducer()
    let content = Interactive(action: {}) { _ in Text(model.label) }
    let viewport = Size(width: 100, height: 40)
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    try producer.dispatch(InputState(pointerPosition: Point(x: 10, y: 10)), onChange: {})
    let builds = producer.builds
    model.label = "Updated"
    try producer.refresh(content: content, viewport: viewport, context: context, onChange: {})
    #expect(producer.builds == builds)
    #expect(producer.paint().commands.contains { if case .text(_, "Updated", _, _) = $0 { true } else { false } })
  }

  @Test func inactiveRetainedWindowHasNoScheduledFrames() {
    let runtime = WindowRuntime()
    runtime.content = Interactive(action: {}) { _ in Text("Idle") }
    _ = runtime.renderScheduled(.content, viewport: Size(width: 100, height: 40), onChange: {})
    #expect(!runtime.needsAnimationFrame)
    #expect(runtime.scheduler.nextFrame == nil)
  }

  @Test func customBackgroundPreservesOrderAndDoesNotClaimFocus() throws {
    let content = Text("Foreground").background(Text("Background")).padding(4).clipped()
    let context = BlockContext()
    let scene = NodeScene()
    let rect = Rect(x: 0, y: 0, width: 100, height: 40)
    try scene.update(content, context: context)
    try scene.layout(in: rect)
    scene.prepare(viewport: rect.size)
    let actual = scene.paint(cullingEnabled: false)
    context.interaction.beginFrame(input: InputState(), processingInput: false)
    var expected = DrawList()
    BlockEngine.draw(content, into: &expected, in: rect, context: context)
    context.interaction.endFrame()
    #expect(actual.commands == expected.commands)
  }
}
