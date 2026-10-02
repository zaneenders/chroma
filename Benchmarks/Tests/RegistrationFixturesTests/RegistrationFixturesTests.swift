import Chroma
import RegistrationFixtures
import Testing

@MainActor
struct RegistrationFixturesTests {
  @Test(arguments: RegistrationMode.allCases)
  func coalescedCallbacksAreFreshAndPresentationReturnsToIdle(mode: RegistrationMode) {
    let fixture = RegistrationFixture(mode: mode, rows: 10_000)
    defer { fixture.close() }
    #expect(fixture.host.renderIfNeeded() != nil)
    fixture.selectIncrement()
    fixture.activateTwice()
    #expect(fixture.actions == 2)
    #expect(fixture.host.renderIfNeeded() != nil)
    #expect(fixture.actions == 2)
    #expect(fixture.host.renderIfNeeded() == nil)
  }

  @Test(arguments: RegistrationMode.allCases)
  func registrationWorkIsVirtualizedAndBaselineIsExplicit(mode: RegistrationMode) {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let fixture = RegistrationFixture(mode: mode, rows: 10_000)
    fixture.host.renderIfNeeded()
    fixture.selectIncrement()
    let rowsBefore = fixture.rowConstructions
    PipelineMetrics.reset()
    fixture.activateTwice()
    let work = PipelineMetrics.snapshot
    #expect(fixture.rowConstructions > rowsBefore)
    #expect(fixture.rowConstructions - rowsBefore < 200)
    #expect(work.registrations > 0)
    #expect(work.liveResolvedNodes == 0)
    #expect(work.peakResolvedNodes > 0)
    switch mode {
    case .paintFree:
      #expect(work.paints == 0)
      #expect(work.drawingCommands == 0)
      #expect(work.compatibilityFallbacks == 0)
    case .legacyPaintTraversal:
      #expect(work.paints > 0)
      #expect(work.drawingCommands > 0)
      #expect(work.compatibilityFallbacks == 2)
      #expect(work.compatibilityFallbackTypes == [String(reflecting: LegacyRegistrationRoot.self): 2])
    }
    fixture.close()
    #expect(PipelineMetrics.snapshot.liveResolvedNodes == 0)
    #expect(PipelineMetrics.snapshot.liveObservationSubscriptions == 0)
  }

  @Test(arguments: RegistrationMode.allCases)
  func idlePollsProduceNoFramesOrPipelineWork(mode: RegistrationMode) {
    PipelineMetrics.isEnabled = true
    defer { PipelineMetrics.isEnabled = false }
    let fixture = RegistrationFixture(mode: mode, rows: 100)
    defer { fixture.close() }
    #expect(fixture.host.renderIfNeeded() != nil)
    fixture.selectIncrement()
    fixture.activateTwice()
    fixture.scroll()
    #expect(fixture.host.renderIfNeeded() != nil)
    PipelineMetrics.reset()
    let before = PipelineMetrics.snapshot
    let rowsBefore = fixture.rowConstructions
    for _ in 0..<1_000 {
      #expect(fixture.host.renderIfNeeded() == nil)
    }
    #expect(PipelineMetrics.snapshot == before)
    #expect(fixture.rowConstructions == rowsBefore)
    #expect(fixture.actions == 2)
  }

  @Test(arguments: RegistrationMode.allCases)
  func eventsBeforeInitialFrameStayOrdered(mode: RegistrationMode) {
    let fixture = RegistrationFixture(mode: mode, rows: 100)
    defer { fixture.close() }
    fixture.host.sendInput(InputState(commands: [.navigation(.nextFocus)]))
    fixture.host.sendInput(InputState(commands: [.action(.activate)]))
    fixture.host.sendInput(InputState(commands: [.action(.activate)]))
    #expect(fixture.actions == 0)
    let frame = fixture.host.renderIfNeeded()
    #expect(frame != nil)
    #expect(fixture.host.lastFrame == frame)
    #expect(fixture.actions == 2)
    #expect(fixture.host.renderIfNeeded() == nil)
  }

  @Test func modesPaintTheSameFramesForTheSameInputSequence() {
    let current = RegistrationFixture(mode: .paintFree, rows: 100)
    let baseline = RegistrationFixture(mode: .legacyPaintTraversal, rows: 100)
    defer {
      current.close()
      baseline.close()
    }
    let frame = current.host.renderIfNeeded()
    #expect(frame == baseline.host.renderIfNeeded())
    #expect(current.rowConstructions == baseline.rowConstructions)
    for fixture in [current, baseline] {
      fixture.selectIncrement()
      fixture.activateTwice()
      fixture.scroll()
    }
    #expect(current.actions == baseline.actions)
    #expect(current.actions == 2)
    #expect(current.host.renderIfNeeded() == baseline.host.renderIfNeeded())
    #expect(current.actions == 2)
    #expect(baseline.actions == 2)
    #expect(current.rowConstructions == baseline.rowConstructions)
  }
}
