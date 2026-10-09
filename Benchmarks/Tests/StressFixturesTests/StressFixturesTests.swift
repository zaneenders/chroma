import Chroma
import ChromaTesting
import StressFixtures
import Testing

@MainActor
struct StressFixturesTests {
  @Test func optionsRejectInvalidWorkloads() throws {
    for arguments in [["--rows", "0"], ["--depth", "-1"], ["--panes"], ["--unknown", "2"], ["--identified", "2"]] {
      #expect(throws: StressOptions.InvalidOption.self) { try StressOptions(arguments: arguments) }
    }
    let options = try StressOptions(arguments: ["--depth", "0", "--warmup", "0"])
    #expect(options.configuration.depth == 0)
    #expect(options.warmup == 0)
    #expect(options.configuration.identified)
    #expect(try !StressOptions(arguments: ["--identified", "0"]).configuration.identified)
  }

  @Test(arguments: [false, true])
  func burstIsFreshVirtualizedPaintFreeAndReturnsToIdle(identified: Bool) {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let scene = StressScene(
      configuration: StressConfiguration(rows: 10_000, panes: 3, depth: 4, events: 12, identified: identified))
    let host = HeadlessHost(size: StressConfiguration.viewport)
    host.content = DeferredBlock { scene.content }
    #expect(!host.render().commands.isEmpty)
    host.sendInput(InputState(commands: [.navigation(.nextFocus)]))
    let rowsBefore = scene.rowConstructions
    PipelineMetrics.reset()
    host.sendInput(InputState(commands: [.action(.activate)]))
    host.sendInput(InputState(commands: [.action(.activate)]))
    for event in 0..<scene.configuration.events { host.sendInput(scene.scrollInput(event: event)) }
    #expect(scene.actions == 2)
    #expect(scene.rowConstructions > rowsBefore)
    #expect(scene.rowConstructions - rowsBefore < 2000)
    #expect(PipelineMetrics.snapshot.registrations > 0)
    #expect(PipelineMetrics.snapshot.paints == 0)
    #expect(PipelineMetrics.snapshot.drawingCommands == 0)
    #expect(host.renderIfNeeded() != nil)
    #expect(scene.actions == 2)
    PipelineMetrics.reset()
    let work = PipelineMetrics.snapshot
    let rows = scene.rowConstructions
    for _ in 0..<1000 { #expect(host.renderIfNeeded() == nil) }
    #expect(PipelineMetrics.snapshot == work)
    #expect(scene.rowConstructions == rows)
    host.close()
    #expect(PipelineMetrics.snapshot.liveResolvedNodes == 0)
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 0)
  }
}
