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

  @Test(arguments: [false, true])
  func queuedPointerSelectionWorksBeforeFirstPresentation(ignored: Bool) {
    let host = HeadlessHost(size: Size(width: 200, height: 80))
    defer { host.close() }
    host.build = { buffer, context in
      var context = context
      context.navigationIgnored = ignored
      return buffer.text(Text("abcdef").selectable(), context: context)
    }
    let start = Point(x: 0, y: 1)
    let end = Point(x: host.runtime.context.fontMetrics.cellAdvance * 3, y: 1)
    host.sendInput(InputState(pointerPosition: start, pointerDown: true, pointerPressed: true))
    host.sendInput(InputState(pointerPosition: end, pointerDown: true))
    host.sendInput(InputState(pointerPosition: end, pointerReleased: true))
    #expect(host.lastFrame == nil)
    let frame = host.render()
    #expect(host.runtime.interaction.copyText() == "abc")
    #expect(
      frame.paintSnapshot.contains {
        if case .fillRect(_, let color) = $0 { return color == host.runtime.context.theme.focus.selectionBackground }
        return false
      })
    #expect(host.runtime.interaction.dragOrigin == nil)
    #expect((host.runtime.interaction.selectedLeafID == nil) == ignored)
    host.render()
    #expect(host.runtime.interaction.copyText() == "abc")
  }

  @Test func rawKeysUseOneFreshRegistrationAndPreserveReentrantOrder() {
    let host = HeadlessHost()
    defer { host.close() }
    let key = KeyboardInput(chord: KeyChord("x"), text: "x")
    var builds = 0
    var revision = 0
    var seen: [Int] = []
    host.build = { buffer, context in
      builds += 1
      let current = revision
      let child = buffer.button(Button("Target") {}, context: context)
      let scoped = buffer.keyBindings(child, KeyBindings { bind("x", to: .application("run")) }, context: context)
      return buffer.onCommand(scoped, .application("run"), context: context) {
        seen.append(current)
        revision += 1
        if current == 0 { host.sendKeyboardInput(key) }
        return .handled
      }
    }
    host.render()
    host.sendInput(InputState(commands: [.navigation(.nextFocus)]))
    builds = 0
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    host.sendKeyboardInput(key)
    #expect(seen == [0, 1])
    #expect(builds == 2)
    #expect(PipelineMetrics.snapshot.paints == 0)
    host.render()
    #expect(seen == [0, 1])
    #expect(builds == 3)
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
