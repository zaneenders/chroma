import HeadlessBackend
import Testing

@testable import Chroma

@MainActor
struct HeadlessRendererTests {
  @Test func rendersDeterministicFramesAtTheConfiguredViewport() {
    let renderer = HeadlessRenderer(size: Size(width: 120, height: 80))
    renderer.content = Color.yellow

    let first = renderer.render()
    let second = renderer.render()

    #expect(first == second)
    #expect(first.viewport == Size(width: 120, height: 80))
    #expect(
      first.commands == [
        .fillRect(rect: Rect(x: 0, y: 0, width: 120, height: 80), color: .yellow)
      ])
    #expect(renderer.lastFrame == second)
  }

  @Test func runCapturesTheTitleAndRendersOneFrame() {
    let renderer = HeadlessRenderer(size: Size(width: 40, height: 30))
    renderer.content = Color.white

    renderer.run(title: "Snapshot")

    #expect(renderer.title == "Snapshot")
    #expect(renderer.lastFrame?.commands.count == 1)
  }

  @Test func repeatedFramesPreserveButtonInteractionState() {
    let renderer = HeadlessRenderer(size: Size(width: 100, height: 50))
    let clickCount = Counter()
    renderer.content = Button("Click", id: WidgetID("headless-button")) {
      clickCount.value += 1
    }

    _ = renderer.render()
    _ = renderer.render(
      input: InputState(
        pointerPosition: Point(x: 10, y: 10),
        pointerPressPosition: Point(x: 10, y: 10),
        pointerDown: true,
        pointerPressed: true
      ))
    _ = renderer.render(
      input: InputState(
        pointerPosition: Point(x: 10, y: 10),
        pointerPressPosition: Point(x: 10, y: 10),
        pointerReleased: true
      ))

    #expect(clickCount.value == 1)
  }

  @Test func closeInvokesCallback() {
    let renderer = HeadlessRenderer()
    let closeCount = Counter()
    renderer.onClose = { closeCount.value += 1 }

    renderer.close()

    #expect(closeCount.value == 1)
  }
}

@MainActor
private final class Counter {
  var value = 0
}
