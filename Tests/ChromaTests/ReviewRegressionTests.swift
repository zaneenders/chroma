import HeadlessBackend
import Observation
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct ReviewRegressionTests {
  @Observable final class Model {
    var text = "abcdef"
    var height: Float = 20
  }

  final class Capture {
    var range: Range<Int>?
    var measurements = 0
    var drawnHeight: Float = 0
  }

  struct Editor: PrimitiveBlock {
    let text: String
    let model: Model
    let capture: Capture

    var focusRule: FocusRule { .control }

    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

    func draw(into list: inout DrawList, in rect: Rect, context: RenderContext) {
      let state = context.textInputState(
        id: WidgetID("editor"), in: rect, text: { text }, onChange: { model.text = $0 })
      capture.range = state.selectionRange
    }
  }

  struct Row: PrimitiveBlock {
    let model: Model
    let capture: Capture

    var focusRule: FocusRule { .standard }

    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
      capture.measurements += 1
      return Size(width: proposal.width, height: model.height)
    }

    func draw(into list: inout DrawList, in rect: Rect, context: RenderContext) {
      capture.drawnHeight = rect.size.height
      list.fillRect(rect, color: .white)
    }
  }

  @Test func capturedTextSelectionIsClampedToCurrentText() {
    let model = Model()
    let capture = Capture()
    let renderer = HeadlessRenderer()
    renderer.content = DeferredBlock { Editor(text: model.text, model: model, capture: capture) }
    renderer.render()
    renderer.render(input: InputState(commands: [.navigation(.down), .action(.activate)]))
    renderer.render(input: InputState(textEvents: [.selectAll]))
    model.text = "a"
    renderer.render()
    #expect(capture.range == 0..<1)
    renderer.close()
  }

  @Test func editsUseCurrentCapturedText() {
    let model = Model()
    let capture = Capture()
    let renderer = HeadlessRenderer()
    renderer.content = DeferredBlock { Editor(text: model.text, model: model, capture: capture) }
    renderer.render()
    renderer.render(input: InputState(commands: [.navigation(.down), .action(.activate)]))
    model.text = "a"
    renderer.render(input: InputState(textEvents: [.insert("!")]))
    #expect(model.text == "a!")
    renderer.close()
  }

  @Test func builtInTextFieldHandlesShrinkingCapturedText() {
    let model = Model()
    let renderer = HeadlessRenderer()
    func field(_ text: String) -> TextField {
      TextField(id: WidgetID("editor"), text: { text }, onChange: { model.text = $0 })
    }
    renderer.content = DeferredBlock { field(model.text) }
    renderer.render()
    renderer.render(input: InputState(commands: [.navigation(.down), .action(.activate)]))
    renderer.render(input: InputState(textEvents: [.selectAll]))
    model.text = "a"
    renderer.render()
    model.text = ""
    renderer.render()
    renderer.close()
  }

  @Test func lazyMeasurementsInvalidateAndResubscribe() async {
    let model = Model()
    let capture = Capture()
    let controller = ScrollViewController()
    let renderer = HeadlessRenderer()
    renderer.content = LazyVStack(
      id: WidgetID("stack"), controller: controller,
      rows: [.init(id: WidgetID("row"), content: Row(model: model, capture: capture))])
    var redraws = 0
    renderer.onRedrawRequested = { redraws += 1 }
    renderer.render()
    #expect(capture.measurements == 1)
    for height: Float in [50, 80] {
      redraws = 0
      model.height = height
      await drainObservationChanges()
      #expect(redraws > 0)
      renderer.render()
      #expect(capture.drawnHeight == height)
    }
    #expect(capture.measurements == 3)
    renderer.render()
    #expect(capture.measurements == 3)
    renderer.close()
  }

  final class InputCapture {
    var clicks = 0
    var inputs: [InputState] = []
  }

  struct InputProbe: PrimitiveBlock {
    let capture: InputCapture

    var focusRule: FocusRule { .control }

    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

    func draw(into list: inout DrawList, in rect: Rect, context: RenderContext) {
      capture.inputs.append(context.input)
      if context.buttonState(id: WidgetID("probe"), in: rect).clicked {
        capture.clicks += 1
      }
    }
  }

  @Test func registrationRefreshDoesNotReplayClickOrInput() {
    let capture = InputCapture()
    let renderer = HeadlessRenderer()
    defer { renderer.close() }
    renderer.content = InputProbe(capture: capture)
    renderer.render()
    renderer.render(input: InputState(commands: [.navigation(.down), .action(.activate)]))
    #expect(capture.clicks == 1)
    capture.inputs = []
    let textInput = InputState(textEvents: [.insert("x")])
    renderer.render(input: textInput)
    #expect(capture.clicks == 1)
    #expect(capture.inputs == [InputState(), textInput])

    // The refresh must still allow a new activation in the actual input pass.
    renderer.render(
      input: InputState(
        commands: [.action(.activate)], textEvents: [.insert("y")]))
    #expect(capture.clicks == 2)
  }

  @Test func registrationRefreshDoesNotReplayPointerOrScrollEdges() {
    let capture = InputCapture()
    let renderer = HeadlessRenderer()
    defer { renderer.close() }
    renderer.content = InputProbe(capture: capture)
    renderer.render()
    renderer.render(
      input: InputState(
        pointerPosition: Point(x: 10, y: 10), pointerPressPosition: Point(x: 10, y: 10),
        pointerDown: true, pointerPressed: true, scrollDelta: Point(x: 0, y: -10)))
    capture.inputs = []
    let input = InputState(pointerDown: true, textEvents: [.insert("x")])
    renderer.render(input: input)
    #expect(capture.inputs == [InputState(), input])
  }

  @Test func lazyMeasurementsInvalidateBeforeImmediateRender() async {
    let model = Model()
    let capture = Capture()
    let controller = ScrollViewController()
    let renderer = HeadlessRenderer()
    defer { renderer.close() }
    renderer.content = LazyVStack(
      id: WidgetID("stack"), controller: controller,
      rows: [.init(id: WidgetID("row"), content: Row(model: model, capture: capture))])
    renderer.render()
    for height: Float in [50, 80, 30] {
      model.height = height
      renderer.render()
      #expect(capture.drawnHeight == height)
    }
    #expect(capture.measurements == 4)
    // Queued callbacks for replaced measurements must not invalidate the new cache.
    await drainObservationChanges()
    renderer.render()
    #expect(capture.measurements == 4)
  }

  @Test func lazyMeasurementsReflectChangesFromInputHandlersInSameFrame() {
    let model = Model()
    let capture = Capture()
    let controller = ScrollViewController()
    let renderer = HeadlessRenderer()
    defer { renderer.close() }
    renderer.content = LazyVStack(
      id: WidgetID("stack"), controller: controller,
      rows: [.init(id: WidgetID("row"), content: Row(model: model, capture: capture))]
    ).onCommand(.application("resize")) {
      model.height = 80
      return .handled
    }
    renderer.render()
    renderer.render(input: InputState(commands: [.application("resize")]))
    #expect(capture.drawnHeight == 80)
    #expect(capture.measurements == 2)
  }

}
