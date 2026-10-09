import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct ObservationDeliveryTests {
  @Test(.timeLimit(.minutes(1)))
  func lazyMeasurementsRequestRedrawUsingMainActorTasks() async throws {
    let model = LazyLayoutCacheTests.Model()
    let capture = LazyLayoutCacheTests.Capture()
    let renderer = HeadlessHost()
    defer { renderer.close() }
    let controller = ScrollViewController()
    let scroll = ScrollView(
      controller: controller,
      rows: [
        .init(
          id: WidgetID("row"),
          build: { buffer, context in
            LazyLayoutCacheTests.row(model: model, capture: capture, into: &buffer, context: context)
          })
      ])
    renderer.build = { buffer, context in
      buffer.scrollView(scroll, context: context.keyed(WidgetID("stack")))
    }
    let (redraws, continuation) = AsyncStream<Void>.makeStream()
    defer { continuation.finish() }
    renderer.onRedrawRequested = { continuation.yield(()) }
    var iterator = redraws.makeAsyncIterator()
    renderer.render()
    for height: Float in [50, 80] {
      model.height = height
      let redraw: Void? = await iterator.next()
      try #require(redraw != nil)
      renderer.render()
      #expect(capture.drawnHeight == height)
    }
    #expect(capture.measurements == 3)
  }
}
