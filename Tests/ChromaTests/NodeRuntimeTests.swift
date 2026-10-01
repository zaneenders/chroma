import Observation
import Testing

@testable import Chroma

@MainActor
struct NodeRuntimeTests {
  @Observable final class Model {
    var modal = false
    var label = "Run"
    var actions: [String] = []
  }

  private struct Content: Block {
    let model: Model
    var body: some Block {
      VStack {
        if model.modal {
          Button("Modal") { model.actions.append("modal") }
        } else {
          Button(model.label) {
            model.modal = true
            model.actions.append("open")
          }
        }
      }
    }
  }

  @Test func modalOpeningBetweenEventsRefreshesWithoutPainting() {
    let runtime = WindowRuntime()
    runtime.nodeLifecycleEnabled = true
    let model = Model()
    runtime.content = Content(model: model)
    let viewport = Size(width: 200, height: 100)
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    #expect(model.actions == ["open", "modal"])
    #expect(runtime.nodePaints == 1)
    #expect(runtime.nodeBuilds == 2)
  }

  @Test func eightQueuedEventsShareOneScheduledPaintAndOneBuild() {
    let runtime = WindowRuntime()
    runtime.nodeLifecycleEnabled = true
    var actions: [Int] = []
    runtime.content = Button("Run") { actions.append(actions.count) }
    _ = runtime.render(viewport: Size(width: 100, height: 40), input: InputState(), onChange: {})
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    for _ in 0..<8 {
      runtime.dispatchInput { runtime.handleInput(InputState(commands: [.action(.activate)])) }
    }
    #expect(runtime.nodePaints == 1)
    _ = runtime.renderScheduled(.content, viewport: Size(width: 100, height: 40), onChange: {})
    #expect(actions == Array(0..<8))
    #expect(runtime.nodePaints == 2)
    #expect(runtime.nodeBuilds == 1)
    runtime.reset()
  }

  @Test func listSliceRefreshesObservedRowsBetweenEventsWithoutPainting() {
    let runtime = WindowRuntime()
    runtime.nodeLifecycleEnabled = true
    let model = Model()
    runtime.content = FixedHeightList(count: 1000, rowHeight: 30, overscan: 0) { index in
      Button("\(model.label)-\(index)") {
        model.label = "Changed"
        model.actions.append("\(index)")
      }
    }
    let viewport = Size(width: 200, height: 60)
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    let point = Point(x: 10, y: 10)
    runtime.handleInput(InputState(pointerPosition: point, scrollDelta: Point(x: 0, y: -300)))
    runtime.handleInput(InputState(pointerPosition: point, pointerDown: true, pointerPressed: true))
    runtime.handleInput(InputState(pointerPosition: point, pointerReleased: true))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    #expect(model.actions == ["10", "10"])
    #expect(runtime.nodePaints == 1)
    #expect(runtime.nodeBuilds == 2)
    let commands = runtime.renderScheduled(.content, viewport: viewport, onChange: {}).commands
    #expect(
      commands.contains { command in
        if case .text(_, let text, _, _) = command { return text == "Changed-10" }
        return false
      })
  }

  @Test func replacementRemovalAndResizeRefreshTheRuntimeSnapshot() {
    let runtime = WindowRuntime()
    runtime.nodeLifecycleEnabled = true
    var actions = 0
    let viewport = Size(width: 200, height: 60)
    runtime.content = Button("Run") { actions += 1 }
    _ = runtime.render(viewport: viewport, input: InputState(), onChange: {})
    runtime.content = Text("Removed")
    runtime.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    runtime.handleInput(InputState(commands: [.action(.activate)]))
    #expect(actions == 0)
    #expect(runtime.nodePaints == 1)
    let resized = Size(width: 300, height: 100)
    _ = runtime.renderScheduled(.content, viewport: resized, onChange: {})
    #expect(runtime.interaction.viewport.size == resized)
    #expect(runtime.interaction.registrations.buttonActions.isEmpty)
  }

  @Test func scopesRouteCommandsWithoutPaintingAndSupportEntryAndExit() {
    let runtime = WindowRuntime()
    runtime.nodeLifecycleEnabled = true
    var actions = 0
    runtime.content = VStack {
      Button("Run") { actions += 1 }
    }.onCommand(.application("run")) {
      actions += 10
      return .handled
    }
    _ = runtime.render(viewport: Size(width: 100, height: 40), input: InputState(), onChange: {})
    for command: Command in [
      .navigation(.nextFocus), .navigation(.stepIn), .action(.activate),
      .application("run"), .navigation(.stepOut),
    ] {
      runtime.handleInput(InputState(commands: [command]))
    }
    #expect(actions == 12)
    #expect(runtime.nodePaints == 1)
    #expect(runtime.nodeBuilds == 1)
  }
}
