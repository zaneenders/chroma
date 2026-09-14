import HeadlessBackend
import Testing

@testable import Chroma

@MainActor
struct ObservationDeliveryTests {
  @Test(.timeLimit(.minutes(1)))
  func lazyMeasurementsRequestRedrawUsingMainActorTasks() async throws {
    let model = ReviewRegressionTests.Model()
    let capture = ReviewRegressionTests.Capture()
    let renderer = HeadlessRenderer()
    defer { renderer.close() }
    renderer.content = LazyVStack(
      id: WidgetID("stack"), controller: ScrollViewController(),
      rows: [
        .init(
          id: WidgetID("row"),
          content: ReviewRegressionTests.Row(model: model, capture: capture))
      ])
    let (redraws, continuation) = AsyncStream<Void>.makeStream()
    defer { continuation.finish() }
    renderer.onRedrawRequested = { continuation.yield(()) }
    var iterator = redraws.makeAsyncIterator()
    renderer.render()
    for height: Float in [50, 80] {
      model.height = height
      // Await the real redraw, not elapsed time or an assumed executor order.
      let redraw: Void? = await iterator.next()
      try #require(redraw != nil)
      renderer.render()
      #expect(capture.drawnHeight == height)
    }
    #expect(capture.measurements == 3)
  }
}
