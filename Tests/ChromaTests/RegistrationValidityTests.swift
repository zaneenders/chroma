import ChromaTesting
import Observation
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct RegistrationValidityTests {
  @Observable final class Model {
    var width: Float = 100
    var callbackValue = 0
    var visible = true
  }

  final class Counters {
    var draws = 0
    var activatedValue: Int?
  }

  struct Control: PrimitiveBlock {
    let model: Model
    let counters: Counters
    var focusRule: FocusRule { .control }

    func sizeThatFits(_ proposal: Size, context: BlockContext) -> Size {
      Size(width: model.width, height: 100)
    }

    func draw(into list: inout DrawList, in rect: Rect, context: BlockContext) {
      counters.draws += 1
      let value = model.callbackValue
      let hitRect = Rect(x: rect.minX, y: rect.minY, width: model.width, height: 100)
      _ = context.buttonState(in: hitRect) { counters.activatedValue = value }
    }
  }

  struct Content: Block {
    let model: Model
    let counters: Counters
    @BlockBuilder var body: some Block {
      if model.visible { Control(model: model, counters: counters) }
    }
  }

  @Test func stateChangesInvalidateBeforeDeferredRedrawAndRefreshResubscribes() {
    let model = Model()
    let counters = Counters()
    let host = HeadlessHost(size: Size(width: 300, height: 200))
    host.content = Content(model: model, counters: counters)
    host.renderScheduled()
    counters.draws = 0
    let pointer = InputState(pointerPosition: Point(x: 80, y: 20))
    host.handleInput(pointer)
    #expect(counters.draws == 0)

    model.width = 50
    host.handleInput(pointer)
    #expect(counters.draws == 1)
    #expect(host.runtime.interaction.untrackedLeafState.hovered == nil)
    host.handleInput(pointer)
    #expect(counters.draws == 1)

    model.width = 100
    host.handleInput(pointer)
    #expect(counters.draws == 2)
    #expect(host.runtime.interaction.untrackedLeafState.hovered != nil)
    host.handleInput(pointer)
    #expect(counters.draws == 2)
  }

  @Test func changedCallbacksAndRemovedControlsRemainSafeBeforeRendering() {
    let model = Model()
    let counters = Counters()
    let host = HeadlessHost(size: Size(width: 300, height: 200))
    host.content = Content(model: model, counters: counters)
    host.renderScheduled()
    model.callbackValue = 42
    let point = Point(x: 20, y: 20)
    host.handleInput(InputState(pointerPosition: point))
    host.handleInput(
      InputState(
        pointerPosition: point, pointerDown: true, pointerPressed: true))
    host.handleInput(InputState(pointerPosition: point, pointerReleased: true))
    #expect(counters.activatedValue == 42)

    model.visible = false
    host.handleInput(InputState(pointerPosition: point))
    #expect(host.runtime.interaction.untrackedLeafState.hovered == nil)
  }

  @Test func replacingContentInvalidatesBeforePointerInput() {
    let model = Model()
    let old = Counters()
    let current = Counters()
    let host = HeadlessHost(size: Size(width: 300, height: 200))
    host.content = Content(model: model, counters: old)
    host.renderScheduled()
    old.draws = 0
    host.content = Content(model: model, counters: current)
    let point = Point(x: 20, y: 20)
    host.handleInput(InputState(pointerPosition: point))
    host.handleInput(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    host.handleInput(InputState(pointerPosition: point, pointerReleased: true))
    #expect(old.activatedValue == nil)
    host.renderScheduled()
    #expect(old.activatedValue == nil)
    #expect(current.activatedValue == model.callbackValue)
    #expect(host.runtime.interaction.untrackedLeafState.hovered != nil)
  }

  @Test func viewportChangeInvalidatesRegistrationGeometry() {
    let producer = FrameProducer()
    let interaction = Interaction()
    let viewport = Size(width: 300, height: 200)
    _ = producer.render(
      content: EmptyBlock(), viewport: viewport, input: InputState(),
      context: BlockContext(interaction: interaction), onChange: {})
    #expect(producer.registrationsAreValid(viewport: viewport))
    #expect(!producer.registrationsAreValid(viewport: Size(width: 400, height: 300)))
    producer.reset()
    #expect(!producer.registrationsAreValid(viewport: viewport))
  }
}
