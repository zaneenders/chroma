import ChromaTesting
import Observation
import Testing

@testable import Chroma

@Suite(ControlledObservationDelivery())
@MainActor
struct HeadlessInputTests {
  @Observable final class Model { var text = "First" }

  @Test func observationSchedulesPresentationAndThenReturnsToIdle() async {
    let model = Model()
    let host = HeadlessHost()
    defer { host.close() }
    host.build = { $0.text(Text(model.text), context: $1) }
    #expect(host.renderIfNeeded() != nil)
    await drainObservationChanges()
    #expect(host.renderIfNeeded() == nil)
    model.text = "Second"
    await drainObservationChanges()
    let frame = host.renderIfNeeded()
    #expect(
      frame?.paintSnapshot.contains { command in
        if case .text(_, "Second", _, _) = command { return true }
        return false
      } == true)
    #expect(host.lastFrame == frame)
    await drainObservationChanges()
    #expect(host.renderIfNeeded() == nil)
  }

  @Test func focusRequestsSchedulePresentation() async {
    let host = HeadlessHost()
    let target = FocusTarget()
    defer { host.close() }
    host.build = { buffer, context in
      buffer.focus(target, context: context) { $0.button(Button("Action") {}, context: $1) }
    }
    #expect(host.renderIfNeeded() != nil)
    await drainObservationChanges()
    #expect(host.renderIfNeeded() == nil)
    target.focus()
    #expect(host.renderIfNeeded() != nil)
    #expect(target.isFocused)
    await drainObservationChanges()
    // Resolving a pending focus request can request one confirming frame.
    _ = host.renderIfNeeded()
    await drainObservationChanges()
    #expect(host.renderIfNeeded() == nil)
  }

  @Test func snapshotRenderingDoesNotRedispatchHeldPointerInput() {
    let host = HeadlessHost()
    defer { host.close() }
    var received: [InputState] = []
    host.build = { buffer, context in
      buffer.customLeaf(
        context: context, focusRule: .decorative, measure: { $0 },
        register: { _ in context.interaction.building.inputObservers.append { received.append($0) } },
        paint: { _, _ in })
    }
    _ = host.render()
    let press = InputState(pointerPosition: Point(x: 10, y: 10), pointerDown: true, pointerPressed: true)
    host.sendInput(press)
    _ = host.render()
    _ = host.render()
    #expect(received == [press])
    let release = InputState(pointerPosition: Point(x: 10, y: 10), pointerReleased: true)
    _ = host.render(input: release)
    _ = host.render()
    #expect(received == [press, release])
  }

  @Test func explicitRenderConsumesThePendingRequest() async {
    let host = HeadlessHost()
    defer { host.close() }
    host.build = { $0.text(Text("Static"), context: $1) }
    let frame = host.render()
    #expect(host.lastFrame == frame)
    await drainObservationChanges()
    #expect(host.renderIfNeeded() == nil)
  }
}
