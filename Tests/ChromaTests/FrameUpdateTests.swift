import HeadlessBackend
import Observation
import Testing

@testable import Chroma

@MainActor
struct FrameUpdateTests {
  @Observable final class Model {
    var text = "before"
    var actions = 0
  }

  @Test func actionUpdatesEarlierSiblingInTheSameFrame() {
    let model = Model()
    let renderer = HeadlessRenderer()
    renderer.content = DeferredBlock {
      VStack {
        Text(model.text)
        Button("Change", id: WidgetID("button")) {
          model.actions += 1
          model.text = "after"
        }
      }
    }
    renderer.render()
    let frame = renderer.render(input: InputState(commands: [.action(.activate)]))
    #expect(model.actions == 1)
    #expect(
      frame.commands.contains { command in
        if case .text(_, let text, _, _) = command { return text == "after" }
        return false
      })
    renderer.render()
    #expect(model.actions == 1)
  }

  @Test func textEditingUpdatesEarlierSiblingBeforeDrawing() {
    let model = Model()
    let renderer = HeadlessRenderer()
    renderer.content = DeferredBlock {
      VStack {
        Text(model.text)
        TextField(id: WidgetID("editor"), text: { model.text }, onChange: { model.text = $0 })
      }
    }
    renderer.render()
    renderer.render(input: InputState(commands: [.action(.activate)]))
    let frame = renderer.render(input: InputState(textEvents: [.insert("!")]))
    #expect(model.text == "before!")
    #expect(
      frame.commands.contains { command in
        if case .text(_, let text, _, _) = command { return text == "before!" }
        return false
      })
    renderer.close()
  }

  @Test(ControlledObservationDelivery())
  func externalScrollRequestInvalidatesObservedFrame() async {
    let controller = ScrollViewController()
    let renderer = HeadlessRenderer()
    renderer.content = ScrollView(id: WidgetID("scroll"), controller: controller) {
      Text("hello")
    }
    var requests = 0
    renderer.onRedrawRequested = { requests += 1 }
    renderer.render()
    controller.scrollToBottom()
    await drainObservationChanges()
    #expect(requests == 1)
    renderer.close()
  }

  @Test(.timeLimit(.minutes(1)))
  func caretClockStopsWhenInactive() async throws {
    let (ticks, continuation) = AsyncStream<PendingTick>.makeStream()
    defer { continuation.finish() }
    let clock = CaretClock { duration in
      await withCheckedContinuation { resume in
        continuation.yield(PendingTick(duration: duration, resume: resume))
      }
    }
    var iterator = ticks.makeAsyncIterator()
    #expect(clock.visible)
    clock.setActive(true)
    let first = try #require(await iterator.next())
    #expect(first.duration == .milliseconds(720))
    first.resume.resume()
    let second = try #require(await iterator.next())
    #expect(!clock.visible)
    #expect(second.duration == .milliseconds(480))

    let oldTask = try #require(clock.task)
    // Simulate sleep completing just before deactivation, with its task still queued.
    second.resume.resume()
    clock.setActive(false)
    #expect(clock.visible)
    await oldTask.value
    #expect(clock.visible)

    // An old cancelled tick must not interfere with a newly started clock either.
    clock.setActive(true)
    let third = try #require(await iterator.next())
    let restartedTask = try #require(clock.task)
    third.resume.resume()
    clock.setActive(false)
    clock.setActive(true)
    await restartedTask.value
    #expect(clock.visible)
    let fourth = try #require(await iterator.next())
    #expect(fourth.duration == .milliseconds(720))
    let finalTask = try #require(clock.task)
    clock.setActive(false)
    fourth.resume.resume()
    await finalTask.value
    #expect(clock.visible)
  }

  private struct PendingTick: Sendable {
    let duration: Duration
    let resume: CheckedContinuation<Void, Never>
  }
}
