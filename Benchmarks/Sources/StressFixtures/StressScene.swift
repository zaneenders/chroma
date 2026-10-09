import Chroma
import Observation

public struct StressConfiguration: Codable, Sendable {
  public let rows: Int
  public let panes: Int
  public let depth: Int
  public let events: Int

  public init(rows: Int = 100_000, panes: Int = 3, depth: Int = 8, events: Int = 12) {
    precondition(rows > 0 && panes > 0 && depth >= 0 && events > 0)
    self.rows = rows
    self.panes = panes
    self.depth = depth
    self.events = events
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

  public func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    let capturedActions = actions
    let action = buffer.button(
      Button("Update all panes (\(capturedActions))") { [weak self] in self?.actions = capturedActions + 1 },
      context: context.childScope(0))
    let title = buffer.text(
      Text("\(configuration.panes) panes × \(configuration.rows) identified rows • depth \(configuration.depth)"),
      context: context.childScope(1))
    let panesContext = context.childScope(2)
    let panes = (0..<configuration.panes).map { pane in
      let paneContext = panesContext.keyed(pane)
      let scroll = buffer.scrollView(
        ScrollView(
          data: items, rowHeight: 100, spacing: 2, controller: controllers[pane],
          build: { [weak self] buffer, context, item in
            self?.rowConstructions += 1
            return StressRow(
              index: item.id, pane: pane, revision: capturedActions, depth: self?.configuration.depth ?? 0
            )
            .build(into: &buffer, context: context)
          }), context: paneContext)
      return buffer.sizing(scroll, x: .grow, y: .grow, context: paneContext)
    }
    let horizontal = buffer.stack(panes, axis: .horizontal, spacing: 8, context: panesContext)
    let expanded = buffer.sizing(horizontal, y: .grow, context: panesContext)
    let root = buffer.stack([action, title, expanded], axis: .vertical, spacing: 4, context: context)
    return buffer.padding(root, 8, context: context)
  }

  public func scrollInput(event: Int) -> InputState {
    let pane = event % configuration.panes
    let width = StressConfiguration.viewport.width / Float(configuration.panes)
    return InputState(
      pointerPosition: Point(x: (Float(pane) + 0.5) * width, y: 450),
      scrollDelta: Point(x: 0, y: event % 2 == 0 ? -60 : 60))
  }
}

private struct StressRow {
  let index: Int
  let pane: Int
  let revision: Int
  let depth: Int

  @MainActor func build(into buffer: inout LayoutBuffer, context: LayoutContext) -> LayoutNode {
    buffer.background(
      context: context,
      content: { buffer, context in
        let group = buffer.group(context: context) { buffer, context in
          nested(depth, into: &buffer, context: context)
        }
        return buffer.sizing(group, x: .grow, context: context)
      }, background: { buffer, context in buffer.color(.black, context: context) })
  }

  @MainActor private func nested(_ remaining: Int, into buffer: inout LayoutBuffer, context: LayoutContext)
    -> LayoutNode
  {
    if remaining > 0 {
      return buffer.interactive(
        action: {},
        content: { buffer, context, _ in
          let childContext = context.childScope(0).childScope(0)
          let child = nested(remaining - 1, into: &buffer, context: childContext)
          let expanded = buffer.sizing(child, x: .grow, context: childContext)
          let horizontal = buffer.stack([expanded], axis: .horizontal, context: context.childScope(0))
          let vertical = buffer.stack([horizontal], axis: .vertical, context: context)
          return buffer.padding(vertical, 1, context: context)
        }, context: context)
    }
    let headingContext = context.childScope(0)
    let title = buffer.text(Text("Pane \(pane) / Session \(index)"), context: headingContext.childScope(0))
    let spacer = buffer.spacer(context: headingContext.childScope(1))
    let status = buffer.text(Text("Revision \(revision)"), context: headingContext.childScope(2))
    let heading = buffer.stack([title, spacer, status], axis: .horizontal, context: headingContext)
    let preview = buffer.text(
      Text("A longer session preview exercises text measurement alongside nested layout and controls."),
      context: context.childScope(1))
    let controlsContext = context.childScope(2)
    let open = buffer.button(Button("Open") {}, context: controlsContext.childScope(0))
    let retry = buffer.button(Button("Retry") {}, context: controlsContext.childScope(1))
    let state = buffer.text(Text(index % 3 == 0 ? "Running" : "Ready"), context: controlsContext.childScope(2))
    let controls = buffer.stack([open, retry, state], axis: .horizontal, context: controlsContext)
    return buffer.stack([heading, preview, controls], axis: .vertical, spacing: 2, context: context)
  }
}
