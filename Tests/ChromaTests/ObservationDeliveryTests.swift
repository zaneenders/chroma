import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct ObservationDeliveryTests {
  @Test(.timeLimit(.minutes(1)))
  func lazyMeasurementsRequestRedrawUsingMainActorTasks() async throws {
    let model = FreshRowLayoutTests.Model()
    let capture = FreshRowLayoutTests.Capture()
    let renderer = HeadlessHost()
    defer { renderer.close() }
    renderer.content = ScrollView(
      controller: ScrollViewController(),
      rows: [
        .init(
          id: WidgetID("row"),
          content: FreshRowLayoutTests.Row(model: model, capture: capture))
      ]
    ).id(WidgetID("stack"))
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
    #expect(capture.measurements == 4)
  }
}
