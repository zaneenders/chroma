import Chroma
import Foundation

@MainActor
func benchmark(count: Int, identified: Bool) {
  let producer = FrameProducer()
  let context = BlockContext()
  let controller = ScrollViewController()
  let viewport = Size(width: 200, height: 200)
  let data = 0..<count
  let items = identified ? data.map { Item(id: $0) } : []
  let makeView: () -> ScrollView = {
    if identified {
      return ScrollView(data: items, rowHeight: 20, controller: controller) { _ in
        Color.white
      }
    }
    return ScrollView(data: data, rowHeight: 20, controller: controller) { _ in Color.white }
  }
  for iteration in 0..<6 {
    let start = ProcessInfo.processInfo.systemUptime
    let view = makeView()
    let list = producer.render(
      content: view, viewport: viewport,
      input: InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -1)),
      context: context, onChange: {})
    let duration = (ProcessInfo.processInfo.systemUptime - start) * 1000
    print(
      "\(count) \(identified ? "identified" : "unkeyed") \(iteration == 0 ? "cold" : "warm") \(duration) ms \(list.commands.count) commands"
    )
  }
}

struct Item: Identifiable {
  let id: Int
}

@main
struct InputFrameBenchmark {
  @MainActor static func main() {
    for count in [1_000, 100_000, 1_000_000] {
      benchmark(count: count, identified: false)
      benchmark(count: count, identified: true)
    }
  }
}
