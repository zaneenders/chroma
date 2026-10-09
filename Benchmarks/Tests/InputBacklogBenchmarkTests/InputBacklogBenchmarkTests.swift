import Testing

@testable import InputBacklogBenchmark

struct InputBacklogBenchmarkTests {
  @Test func defaultsAndLimitsAreExplicit() throws {
    let defaults = try BacklogOptions(arguments: [])
    #expect(defaults.events == 180 && defaults.inputHz == 60 && defaults.trials == 3)
    let options = try BacklogOptions(arguments: ["--workload", "markdown", "--axes", "2", "--depth", "0"])
    #expect(options.workload == "markdown" && options.axes == 2 && options.depth == 0)
    for arguments in [
      ["--events", "0"], ["--events", "10001"], ["--axes", "3"], ["--trials", "21"],
      ["--input-hz", "nan"], ["--depth", "-1"], ["--workload", "native"], ["--rows"],
    ] {
      #expect(throws: BacklogOptions.InvalidOption.self) { try BacklogOptions(arguments: arguments) }
    }
  }

  @Test func distributionsUseLowerMedianNearestRankAndNoFabricatedMissingValues() {
    let empty = Distribution(seconds: [])
    #expect(empty.samples == 0 && empty.p50MS == nil && empty.p95MS == nil)
    let values = Distribution(seconds: [0.004, 0.001, 0.003, 0.002])
    #expect(values.samples == 4 && values.p50MS == 2 && values.p95MS == 4 && values.maximumMS == 4)
  }

  @Test func missingLastFrameKeepsRecoveryUnknownAndReportsCoverage() {
    let records = [
      ApplicationRecord(
        sequence: 0, logicalSample: 0, axis: "vertical", intendedSourceTime: 1,
        emittedTime: 1.01, start: 1.02, end: 1.03, firstDrawCompletion: 1.05, processCPUSeconds: 0.002),
      ApplicationRecord(
        sequence: 1, logicalSample: 1, axis: "vertical", intendedSourceTime: 1.1,
        emittedTime: 1.11, start: 1.12, end: 1.13, firstDrawCompletion: nil, processCPUSeconds: 0.003),
    ]
    let report = TrialReport(
      trial: 0, applications: records, drawCompletions: [1.05], sourceStart: 1, sourceEnd: 1.2,
      inputDrainEnd: 1.13, sourceLateness: [0.01, 0.01], peakWaitingLogicalSamples: 1,
      idleQuietSeconds: 0.5, idleEstablished: false, drawCommands: 42)
    #expect(report.inputProcessCPU.p50MS == 2 && report.inputProcessCPU.p95MS == 3)
    #expect(report.unrenderedApplications == 1)
    #expect(report.emittedToDrawCompletion.samples == 1)
    #expect(report.recoveryAfterSourceEndMS == nil)
    #expect(report.drawCompletionIntervals.samples == 0)
    #expect(!report.idleEstablished)
  }

  @MainActor @Test func drawAttributionCoversOnlyAppliedInputsAndNeverRewritesHistory() {
    let recorder = BacklogRecorder()
    recorder.drawCompleted(commands: 10, at: 1)
    #expect(recorder.applications.isEmpty && recorder.nextUnrendered == 0)
    for index in 0..<2 {
      recorder.applications.append(
        ApplicationRecord(
          sequence: index, logicalSample: index, axis: "vertical", intendedSourceTime: 2,
          emittedTime: 2, start: 2, end: 3, firstDrawCompletion: nil))
    }
    recorder.drawCompleted(commands: 20, at: 4)
    #expect(recorder.applications.map(\.firstDrawCompletion) == [4, 4])
    recorder.applications.append(
      ApplicationRecord(
        sequence: 2, logicalSample: 2, axis: "vertical", intendedSourceTime: 5,
        emittedTime: 5, start: 5, end: 6, firstDrawCompletion: nil))
    #expect(recorder.applications.last?.firstDrawCompletion == nil)
    recorder.drawCompleted(commands: 30, at: 7)
    recorder.drawCompleted(commands: 30, at: 8)
    #expect(recorder.applications.map(\.firstDrawCompletion) == [4, 4, 7])
    #expect(recorder.nextUnrendered == 3 && recorder.commands == 30)
    #expect(recorder.completions == [1, 4, 7, 8])
  }

}
