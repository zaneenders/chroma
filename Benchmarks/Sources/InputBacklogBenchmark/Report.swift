import Foundation

struct Distribution: Encodable {
  let samples: Int
  let p50MS: Double?
  let p95MS: Double?
  let maximumMS: Double?

  init(seconds: [Double]) {
    let sorted = seconds.sorted()
    samples = sorted.count
    p50MS = sorted.isEmpty ? nil : sorted[(sorted.count - 1) / 2] * 1000
    p95MS = sorted.isEmpty ? nil : sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1] * 1000
    maximumMS = sorted.last.map { $0 * 1000 }
  }
}

struct ApplicationRecord: Encodable {
  let sequence: Int
  let logicalSample: Int
  let axis: String
  let intendedSourceTime: Double
  let emittedTime: Double
  let start: Double
  let end: Double
  var firstDrawCompletion: Double?
  var processCPUSeconds = 0.0
}

struct TrialReport: Encodable {
  let trial: Int
  let applications: [ApplicationRecord]
  let drawCompletions: [Double]
  let inputApplicationWall: Distribution
  let inputProcessCPU: Distribution
  let sourceLateness: Distribution
  let emittedToApplicationStart: Distribution
  let emittedToDrawCompletion: Distribution
  let drawCompletionIntervals: Distribution
  let sourceDurationSeconds: Double
  let inputDrainSeconds: Double
  let recoveryAfterSourceEndMS: Double?
  let unrenderedApplications: Int
  let peakWaitingLogicalSamples: Int
  let idleQuietSeconds: Double
  let idleEstablished: Bool
  let drawCommands: Int

  init(
    trial: Int, applications: [ApplicationRecord], drawCompletions: [Double],
    sourceStart: Double, sourceEnd: Double, inputDrainEnd: Double,
    sourceLateness: [Double], peakWaitingLogicalSamples: Int,
    idleQuietSeconds: Double, idleEstablished: Bool, drawCommands: Int
  ) {
    self.trial = trial
    self.applications = applications
    self.drawCompletions = drawCompletions
    inputApplicationWall = Distribution(seconds: applications.map { $0.end - $0.start })
    inputProcessCPU = Distribution(seconds: applications.map(\.processCPUSeconds))
    self.sourceLateness = Distribution(seconds: sourceLateness)
    emittedToApplicationStart = Distribution(seconds: applications.map { $0.start - $0.emittedTime })
    emittedToDrawCompletion = Distribution(
      seconds: applications.compactMap { record in
        record.firstDrawCompletion.map { $0 - record.emittedTime }
      })
    drawCompletionIntervals = Distribution(seconds: zip(drawCompletions, drawCompletions.dropFirst()).map { $1 - $0 })
    sourceDurationSeconds = sourceEnd - sourceStart
    inputDrainSeconds = inputDrainEnd - sourceStart
    let recovered = applications.last?.firstDrawCompletion
    recoveryAfterSourceEndMS = recovered.map { max(0, $0 - sourceEnd) * 1000 }
    unrenderedApplications = applications.filter { $0.firstDrawCompletion == nil }.count
    self.peakWaitingLogicalSamples = peakWaitingLogicalSamples
    self.idleQuietSeconds = idleQuietSeconds
    self.idleEstablished = idleEstablished
    self.drawCommands = drawCommands
  }
}

@MainActor
final class BacklogRecorder {
  var applications: [ApplicationRecord] = []
  var completions: [Double] = []
  var nextUnrendered = 0
  var commands = 0

  func drawCompleted(commands: Int, at now: Double) {
    completions.append(now)
    self.commands = commands
    while nextUnrendered < applications.count {
      applications[nextUnrendered].firstDrawCompletion = now
      nextUnrendered += 1
    }
  }
}
