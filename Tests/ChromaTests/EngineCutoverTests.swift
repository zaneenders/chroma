import ChromaTesting
import Testing

@testable import Chroma

@MainActor
struct EngineCutoverTests {
  @Test func everyHostUsesRetainedInputWithoutOptInOrDiscardedDrawing() {
    let host = HeadlessHost(size: Size(width: 100, height: 40))
    var actions = 0
    host.content = Button("Run") { actions += 1 }
    host.renderScheduled()
    host.handleInput(InputState(commands: [.navigation(.nextFocus)]))
    let builds = host.runtime.nodeBuilds
    let paints = host.runtime.nodePaints
    for _ in 0..<8 { host.handleInput(InputState(commands: [.action(.activate)])) }
    #expect(actions == 8)
    #expect(host.runtime.nodeBuilds == builds)
    #expect(host.runtime.nodePaints == paints)
    host.renderScheduled()
    #expect(host.runtime.nodePaints == paints + 1)
    host.close()
  }

  @Test func crossAxisSpacersDoNotMakeFitStacksGrow() throws {
    let scene = NodeScene()
    let context = BlockContext()
    let content = VStack {
      HStack {
        Text("Label")
        Spacer()
        Text("Value")
      }
      Button("Visible") {}
    }
    try scene.update(content, context: context)
    try scene.layout(in: Rect(x: 0, y: 0, width: 200, height: 100))
    scene.prepare(viewport: Size(width: 200, height: 100))
    #expect(scene.paint().commands.contains { if case .text(_, "Visible", _, _) = $0 { true } else { false } })
  }
}
