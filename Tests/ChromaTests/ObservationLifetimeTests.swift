import Dispatch
import Observation
import Synchronization
import Testing

@testable import Chroma

private final class SubscriptionLifetimeCounter: Sendable {
  let live = Mutex(0)
  let redraws = Mutex(0)
}

private final class SubscriptionLifetimeProbe: Sendable {
  let counter: SubscriptionLifetimeCounter

  init(_ counter: SubscriptionLifetimeCounter) {
    self.counter = counter
    counter.live.withLock { $0 += 1 }
  }

  deinit { counter.live.withLock { $0 -= 1 } }

  func recordRedraw() {
    counter.redraws.withLock { $0 += 1 }
  }
}

@MainActor
struct ObservationLifetimeTests {
  @Observable final class Model {
    var color = Color.white
  }

  private func drainChanges() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { continuation.resume() }
    }
  }

  private func render(
    _ producer: FrameProducer, model: Model, counter: SubscriptionLifetimeCounter
  ) {
    let probe = SubscriptionLifetimeProbe(counter)
    _ = producer.render(
      content: DeferredBlock { model.color }, viewport: Size(width: 20, height: 20),
      input: InputState(), context: RenderContext(interaction: Interaction()),
      onChange: { probe.recordRedraw() })
  }

  @Test func unchangedFramesRetainOnlyCurrentSubscription() async {
    let model = Model()
    let producer = FrameProducer()
    let counter = SubscriptionLifetimeCounter()
    for _ in 0..<1_000 {
      render(producer, model: model, counter: counter)
      #expect(counter.live.withLock { $0 } == 1)
    }
    await drainChanges()
    #expect(counter.redraws.withLock { $0 } == 0)

    model.color = .yellow
    await drainChanges()
    #expect(counter.redraws.withLock { $0 } == 1)
    #expect(counter.live.withLock { $0 } == 0)

    render(producer, model: model, counter: counter)
    model.color = .black
    await drainChanges()
    #expect(counter.redraws.withLock { $0 } == 2)
    #expect(counter.live.withLock { $0 } == 0)
  }

  @Test func resetReleasesSubscriptionWithoutMutationOrRedraw() async {
    let model = Model()
    let producer = FrameProducer()
    let counter = SubscriptionLifetimeCounter()
    render(producer, model: model, counter: counter)
    #expect(counter.live.withLock { $0 } == 1)

    producer.reset()
    #expect(counter.live.withLock { $0 } == 0)
    producer.reset()
    model.color = .yellow
    await drainChanges()
    #expect(counter.redraws.withLock { $0 } == 0)
  }

  @Test func producerDestructionReleasesSubscriptionWithoutMutation() async {
    let model = Model()
    let counter = SubscriptionLifetimeCounter()
    var producer: FrameProducer? = FrameProducer()
    render(producer!, model: model, counter: counter)
    #expect(counter.live.withLock { $0 } == 1)

    producer = nil
    #expect(counter.live.withLock { $0 } == 0)
    model.color = .yellow
    await drainChanges()
    #expect(counter.redraws.withLock { $0 } == 0)
  }

  @Test func resetDiscardsAlreadyQueuedModelChange() async {
    let model = Model()
    let producer = FrameProducer()
    let counter = SubscriptionLifetimeCounter()
    render(producer, model: model, counter: counter)
    model.color = .yellow
    producer.reset()
    await drainChanges()
    #expect(counter.redraws.withLock { $0 } == 0)
    #expect(counter.live.withLock { $0 } == 0)
  }
}
