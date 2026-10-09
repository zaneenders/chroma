import Chroma
import Observation

public struct StressConfiguration: Codable, Sendable {
  public let rows: Int
  public let panes: Int
  public let depth: Int
  public let events: Int
  public let identified: Bool

  public init(rows: Int = 100_000, panes: Int = 3, depth: Int = 8, events: Int = 12, identified: Bool = true) {
    precondition(rows > 0 && panes > 0 && depth >= 0 && events > 0)
    self.rows = rows
    self.panes = panes
    self.depth = depth
    self.events = events
    self.identified = identified
  }

  public static let viewport = Size(width: 1440, height: 900)
}

@MainActor @Observable
public final class StressScene {
  public let configuration: StressConfiguration
  public private(set) var actions = 0
  @ObservationIgnored public private(set) var rowConstructions = 0
  @ObservationIgnored private let items: [Item]
  @ObservationIgnored private let controllers: [ScrollViewController]

  private struct Item: Identifiable { let id: Int }

  public init(configuration: StressConfiguration = StressConfiguration()) {
    self.configuration = configuration
    items = (0..<configuration.rows).map { Item(id: $0) }
    controllers = (0..<configuration.panes).map { _ in ScrollViewController() }
  }

  public var content: some Block {
    let capturedActions = actions
    return VStack(spacing: 4) {
      Button("Update all panes (\(capturedActions))") { [weak self] in
        self?.actions = capturedActions + 1
      }
      Text("\(configuration.panes) panes × \(configuration.rows) rows • depth \(configuration.depth)")
      HStack(spacing: 8) {
        for pane in 0..<configuration.panes {
          if configuration.identified {
            ScrollView(data: items, rowHeight: 100, spacing: 2, controller: controllers[pane]) { [weak self] item in
              self?.rowConstructions += 1
              return StressRow(
                index: item.id, pane: pane, revision: capturedActions, depth: self?.configuration.depth ?? 0)
            }.sizing(x: .grow, y: .grow)
          } else {
            ScrollView(data: 0..<configuration.rows, rowHeight: 100, spacing: 2, controller: controllers[pane]) {
              [weak self] index in
              self?.rowConstructions += 1
              return StressRow(
                index: index, pane: pane, revision: capturedActions, depth: self?.configuration.depth ?? 0)
            }.sizing(x: .grow, y: .grow)
          }
        }
      }.sizing(y: .grow)
    }.padding(8)
  }

  public func scrollInput(event: Int) -> InputState {
    let pane = event % configuration.panes
    let width = StressConfiguration.viewport.width / Float(configuration.panes)
    return InputState(
      pointerPosition: Point(x: (Float(pane) + 0.5) * width, y: 450),
      scrollDelta: Point(x: 0, y: event % 2 == 0 ? -60 : 60))
  }
}

private struct StressRow: Block {
  let index: Int
  let pane: Int
  let revision: Int
  let depth: Int

  var body: some Block {
    var content: any Block = VStack(spacing: 2) {
      HStack {
        Text("Pane \(pane) / Session \(index)")
        Spacer()
        Text("Revision \(revision)")
      }
      Text("A longer session preview exercises text measurement alongside nested layout and controls.")
      HStack {
        Button("Open") {}
        Button("Retry") {}
        Text(index % 3 == 0 ? "Running" : "Ready")
      }
    }
    for _ in 0..<depth {
      let child = content
      content = Interactive(
        action: {},
        content: { _ in
          VStack { HStack { child.sizing(x: .grow) } }.padding(1)
        })
    }
    return Group { content }.sizing(x: .grow).background(Color.black)
  }
}
