import Chroma
import ChromaTesting
import Foundation

@MainActor
func benchmark(count: Int, identified: Bool, rebuildContent: Bool, explicitRevision: Bool = false) {
  let controller = ScrollViewController()
  let host = HeadlessHost(size: Size(width: 200, height: 200))
  let data = 0..<count
  let items = identified ? data.map { Item(id: $0) } : []
  let makeView: () -> ScrollView = {
    if identified {
      return ScrollView(
        data: items, rowHeight: 20, controller: controller,
        identityRevision: explicitRevision ? .init(source: "items", revision: 0) : nil
      ) { _ in
        Color.white
      }
    }
    return ScrollView(data: data, rowHeight: 20, controller: controller) { _ in Color.white }
  }
  // App.run keeps a deferred root alive and reevaluates its body during traversal.
  if rebuildContent { host.content = DeferredBlock { makeView() } }
  for iteration in 0..<6 {
    let start = ProcessInfo.processInfo.systemUptime
    if !rebuildContent { host.content = makeView() }
    let renderStart = ProcessInfo.processInfo.systemUptime
    let list = host.render(
      input: InputState(pointerPosition: Point(x: 10, y: 10), scrollDelta: Point(x: 0, y: -1)))
    let end = ProcessInfo.processInfo.systemUptime
    print(
      "\(count) \(explicitRevision ? "revisioned" : identified ? "identified" : "unkeyed") \(rebuildContent ? "deferred-root" : "replace-root") "
        + "\(iteration == 0 ? "cold" : "warm") total=\((end - start) * 1000) ms "
        + "setup=\((renderStart - start) * 1000) ms render=\((end - renderStart) * 1000) ms "
        + "\(list.commands.count) commands"
    )
  }
  host.close()
}

struct Item: Identifiable {
  let id: Int
}

@main
struct InputFrameBenchmark {
  @MainActor static func main() {
    for count in [1_000, 100_000, 1_000_000] {
      for rebuildContent in [false, true] {
        benchmark(count: count, identified: false, rebuildContent: rebuildContent)
        benchmark(count: count, identified: true, rebuildContent: rebuildContent)
        benchmark(count: count, identified: true, rebuildContent: rebuildContent, explicitRevision: true)
      }
    }
  }
}
