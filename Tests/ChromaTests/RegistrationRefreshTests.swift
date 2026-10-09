import ChromaTesting
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct RegistrationRefreshTests {
  final class InputCapture {
    var clicks = 0
    var inputs: [InputState] = []
  }

  @MainActor struct InputProbe {

    func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
      let context = context.component(Self.self)
      return buffer.customLeaf(
        context: context, focusRule: focusRule,
        measure: { self.sizeThatFits($0, context: context) },
        register: { self.register(in: $0, context: context) },
        paint: { self.paint(into: &$0, in: $1, context: context) })
    }

    func register(in rect: Rect, context: LayoutContext) {
      _ = context.buttonState(id: WidgetID("probe"), in: rect) { capture.clicks += 1 }
      context.registerInputHandler { capture.inputs.append($0) }
    }

    let capture: InputCapture

    var focusRule: FocusRule { .control }

    @MainActor func sizeThatFits(_ proposal: Size, context: LayoutContext) -> Size { proposal }

    func paint(into list: inout DrawList, in rect: Rect, context: LayoutContext) {

    }
  }

  @Test func registrationRefreshDoesNotReplayClickOrInput() {
    let capture = InputCapture()
    let renderer = HeadlessHost()
    defer { renderer.close() }
    renderer.build = { buffer, context in
      return InputProbe(capture: capture).build(into: &buffer, context: context)
    }
    renderer.render()
    renderer.render(input: InputState(commands: [.navigation(.down), .action(.activate)]))
    #expect(capture.clicks == 1)
    capture.inputs = []
    let textInput = InputState(textEvents: [.insert("x")])
    renderer.render(input: textInput)
    #expect(capture.clicks == 1)
    #expect(capture.inputs == [textInput])

    renderer.render(
      input: InputState(
        commands: [.action(.activate)], textEvents: [.insert("y")]))
    #expect(capture.clicks == 2)
  }

  @Test func registrationRefreshDoesNotReplayPointerOrScrollEdges() {
    let capture = InputCapture()
    let renderer = HeadlessHost()
    defer { renderer.close() }
    renderer.build = { buffer, context in
      return InputProbe(capture: capture).build(into: &buffer, context: context)
    }
    renderer.render()
    renderer.render(
      input: InputState(
        pointerPosition: Point(x: 10, y: 10), pointerPressPosition: Point(x: 10, y: 10),
        pointerDown: true, pointerPressed: true, scrollDelta: Point(x: 0, y: -10)))
    capture.inputs = []
    let input = InputState(pointerDown: true, textEvents: [.insert("x")])
    renderer.render(input: input)
    #expect(capture.inputs == [input])
  }
}
