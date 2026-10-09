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
    host.setContent(DeferredBlock { Text(model.text) })
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
    host.setContent(Button("Action") {}.focusTarget(target))
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

  @Test func explicitRenderConsumesThePendingRequest() async {
    let host = HeadlessHost()
    defer { host.close() }
    host.setContent(Text("Static"))
    let frame = host.render()
    #expect(host.lastFrame == frame)
    await drainObservationChanges()
    #expect(host.renderIfNeeded() == nil)
  }
}
