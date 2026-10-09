import Foundation

struct TraceError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

struct TraceEvent: Decodable {
  let phase: String
  let start: Double
  let end: Double
  let frame: Int
  var value: Double?
  var protocolMilliseconds: UInt32?
  var presentation: Presentation?
  var work: [String: Int]?

  struct Presentation: Decodable {
    var time: Double?
    let clockTime: Double
  }

  var isAxis: Bool { phase == "scrollHorizontal" || phase == "scrollVertical" }
  var isInput: Bool { phase == "input" || phase == "momentumInput" }
  var successfulSwap: Bool { phase == "eglSwap" && (value ?? 1) == 1 }
}

struct TraceCapture: Decodable {
  var clock: String
  var droppedEvents: Int
  var started: Double
  var ended: Double
  var events: [TraceEvent]
}

func distribution(_ values: [Double], budget: Double? = nil) -> [String: Any] {
  let sorted = values.sorted()
  var result: [String: Any] = [
    "samples": sorted.count,
    "p50": sorted.isEmpty ? NSNull() : sorted[(sorted.count - 1) / 2],
    "p95": sorted.isEmpty ? NSNull() : sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1],
    "max": sorted.last.map { $0 as Any } ?? NSNull(),
  ]
  if let budget { result["overBudget"] = values.filter { $0 > budget }.count }
  return result
}

func unionDuration(_ events: [TraceEvent]) -> Double {
  var total = 0.0
  var end = -Double.infinity
  for event in events.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
    total += max(0, event.end - max(event.start, end))
    end = max(end, event.end)
  }
  return total * 1000
}

func intervals(_ values: [Double]) -> [Double] {
  zip(values, values.dropFirst()).compactMap { a, b in b >= a ? 1000 * (b - a) : nil }
}

struct NativeTrace {
  var schemaVersion = 1
  var metadata: [String: Any]
  var capture: TraceCapture

  init(metadata: [String: Any], capture: TraceCapture) {
    self.metadata = metadata
    self.capture = capture
  }

  init(data: Data) throws {
    struct Payload: Decodable {
      let schemaVersion: Int
      let capture: TraceCapture
    }
    let payload = try JSONDecoder().decode(Payload.self, from: data)
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let metadata = root["metadata"] as? [String: Any]
    else { throw TraceError("Missing trace metadata") }
    self.schemaVersion = payload.schemaVersion
    self.metadata = metadata
    self.capture = payload.capture
  }

  func summarize(refreshHz: Double = 60, start: Double = 0, end: Double = .infinity) throws -> [String: Any] {
    guard schemaVersion == 1, capture.clock == "CLOCK_MONOTONIC" else {
      throw TraceError("Unsupported trace schema or clock")
    }
    guard refreshHz.isFinite, (1...1000).contains(refreshHz), start.isFinite, start >= 0, start < end,
      capture.started.isFinite, capture.ended.isFinite, capture.started <= capture.ended,
      capture.droppedEvents >= 0
    else { throw TraceError("Invalid refresh rate or capture range") }
    let events = capture.events.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
    for event in events {
      guard event.start.isFinite, event.end.isFinite, event.end >= event.start,
        event.value?.isFinite != false, event.presentation?.clockTime.isFinite != false,
        event.presentation?.time?.isFinite != false
      else { throw TraceError("Invalid event timing") }
    }
    let selected = events.filter { start <= $0.start - capture.started && $0.start - capture.started < end }
    let byFrame = Dictionary(grouping: selected, by: \.frame)
    let budget = 1000 / refreshHz
    let cpuPhases: Set<String> = [
      "displayDispatch", "input", "momentumInput", "registrationRefresh", "reconciliation",
      "layoutRegistration", "painting", "frameProduction", "frameCPU", "frameObservation",
      "openGLClear", "openGLSubmission", "eglSwap", "displayQueue",
    ]
    var phases: [String: [Double]] = [:]
    for event in selected where cpuPhases.contains(event.phase) {
      phases[event.phase, default: []].append(1000 * (event.end - event.start))
    }
    // wl_pointer.axis_source describes its entire pointer frame, including axes
    // received before it. A render frame may contain several pointer frames.
    var source: String?
    var pendingAxes: [TraceEvent] = []
    var sources: [Int: Set<String>] = [:]
    func finishPointerFrame(complete: Bool) {
      for axis in pendingAxes where start <= axis.start - capture.started && axis.start - capture.started < end {
        sources[axis.frame, default: []].insert(complete ? source ?? "unknown" : "unknown")
      }
      pendingAxes.removeAll(keepingCapacity: true)
      source = nil
    }
    for event in events {
      if event.phase == "fingerSource" { source = "finger" }
      if event.phase == "otherSource" { source = "otherSource" }
      if event.isAxis { pendingAxes.append(event) }
      if event.phase == "pointerFrame" { finishPointerFrame(complete: true) }
    }
    // Old captures lack boundaries; saturated captures may end mid-group.
    // Neither establishes a trustworthy source for the remaining axes.
    finishPointerFrame(complete: false)
    var unavailable: [(Double, Double)] = []
    var blockedSince: Double? = events.contains { $0.phase == "readiness" } ? capture.started : nil
    for event in events where event.phase == "readiness" {
      if event.value == 0, blockedSince == nil { blockedSince = event.start }
      if event.value == 1, let blocked = blockedSince {
        unavailable.append((blocked, event.start))
        blockedSince = nil
      }
    }
    if let blockedSince { unavailable.append((blockedSince, capture.ended)) }

    var frameStarts: [Int: Double] = [:]
    for event in selected where event.phase == "frameStart" { frameStarts[event.frame] = event.start }
    let starts = frameStarts.sorted { $0.key < $1.key }
    var modes: [Int: String] = [:]
    var groups: [String: [Double]] = [:]
    var latencies: [String: [Double]] = [:]
    for (frame, timestamp) in starts {
      let current = byFrame[frame]!
      let names = Set(current.map(\.phase))
      let horizontal = names.contains("scrollHorizontal")
      let vertical = names.contains("scrollVertical")
      let mode: String
      if horizontal || vertical {
        let direction = horizontal && vertical ? "diagonal" : horizontal ? "horizontal" : "vertical"
        let frameSources = sources[frame] ?? ["unknown"]
        mode = (frameSources.count == 1 ? frameSources.first! : "mixed") + ":" + direction
      } else {
        mode = names.contains("momentumInput") ? "momentum" : "other"
      }
      modes[frame] = mode
      groups[mode, default: []].append(unionDuration(current.filter { $0.isInput || $0.phase == "frameCPU" }))
      let swap = current.first { $0.successfulSwap }
      let callback = current.first { $0.phase == "frameCallback" }
      let presented = current.first { $0.phase == "presented" }?.presentation
      if let swap, let callback {
        latencies["swapReturnToCallbackDelivery", default: []].append(1000 * (callback.start - swap.end))
      }
      if let swap, let time = presented?.time {
        latencies["swapReturnToPresentation", default: []].append(1000 * (time - swap.end))
      }
      let requests = current.filter { $0.phase == "schedulerDemandAge" }.compactMap { event in
        event.value.map { event.start - $0 }
      }
      if let requested = requests.min(), requested <= timestamp {
        let wait = 1000 * (timestamp - requested)
        let blocked = 1000 * unavailable.reduce(0) { $0 + max(0, min($1.1, timestamp) - max($1.0, requested)) }
        latencies["requestToFrameStart", default: []].append(wait)
        latencies["requestWaitWhileNotReady", default: []].append(blocked)
        latencies["requestWaitWhileReady", default: []].append(max(0, wait - blocked))
      }
      for event in current where event.isAxis {
        if event.start <= timestamp {
          latencies["axisReceiptToFrameStart", default: []].append(1000 * (timestamp - event.start))
        }
        if let swap {
          latencies["axisReceiptToSwapReturn", default: []].append(1000 * (swap.end - event.start))
          if let time = presented?.time {
            latencies["axisReceiptToPresentation", default: []].append(1000 * (time - event.start))
          }
        }
      }
    }
    let axes = selected.filter(\.isAxis)
    let submittedFrames = Set(selected.filter(\.successfulSwap).map(\.frame))
    let presentedFrames = Set(selected.filter { $0.phase == "presented" && $0.presentation?.time != nil }.map(\.frame))
    let axisCoverage = [
      "received": axes.count,
      "withoutFrameStart": axes.filter { frameStarts[$0.frame] == nil }.count,
      "withoutSuccessfulSwap": axes.filter { !submittedFrames.contains($0.frame) }.count,
      "withoutPresentationTime": axes.filter { !presentedFrames.contains($0.frame) }.count,
    ]
    let unframedWork = byFrame.compactMap { frame, current -> Double? in
      guard frameStarts[frame] == nil, current.contains(where: \.isAxis) else { return nil }
      return unionDuration(current.filter(\.isInput))
    }
    let callbacks = selected.filter { $0.phase == "frameCallback" }
    let protocolIntervals = zip(callbacks, callbacks.dropFirst()).compactMap { a, b -> Double? in
      guard let a = a.protocolMilliseconds, let b = b.protocolMilliseconds else { return nil }
      return Double(b &- a)
    }
    let presentations = selected.compactMap { $0.presentation?.clockTime }.sorted()
    var pacing: [Double] = []
    var modeIntervals: [String: [Double]] = [:]
    for (previous, currentStart) in zip(starts, starts.dropFirst()) {
      let (previousFrame, previousTime) = previous
      let (frame, timestamp) = currentStart
      let consecutive = frame > previousFrame && frame - previousFrame == 1
      if consecutive, modes[previousFrame] == modes[frame] {
        modeIntervals[modes[frame]!, default: []].append(1000 * (timestamp - previousTime))
      }
      let current = byFrame[frame]!
      var requests = current.filter { $0.phase == "schedulerDemandAge" }.compactMap { event in
        event.value.map { event.start - $0 }
      }
      requests += current.filter(\.isAxis).map(\.start)
      let demanded =
        modes[previousFrame] == "momentum" && modes[frame] == "momentum"
        || requests.contains { $0 <= previousTime + budget / 1000 }
      if consecutive, demanded { pacing.append(1000 * (timestamp - previousTime)) }
    }
    let workCounters = [
      "bodyEvaluations", "measurements", "measurementCacheHits", "textLayouts",
      "placements", "registrations", "paints", "drawingCommands",
    ]
    var work: [String: Any] = [:]
    for phase in ["input", "momentumInput", "registrationRefresh", "frameProduction"] {
      let samples = selected.filter { $0.phase == phase }.compactMap(\.work)
      var totals: [String: Int] = [:]
      for key in workCounters { totals[key] = samples.reduce(0) { $0 + ($1[key] ?? 0) } }
      work[phase] = ["calls": samples.count, "totals": totals] as [String: Any]
    }
    var counts: [String: Int] = [:]
    for event in selected { counts[event.phase, default: 0] += 1 }
    let failedSwaps = selected.filter { $0.phase == "eglSwap" && $0.value == 0 }.count
    var counters: [String: Any] = [:]
    for name in ["glInstances", "glDrawCalls", "glUploadCalls", "glUploadBytes"] {
      counters[name] = distribution(selected.filter { $0.phase == name }.compactMap(\.value))
    }
    var warnings = [
      "CPU scopes are inclusive wall time (including driver waits); do not add parent and child distributions.",
      "All-frame and callback intervals include deliberate idle gaps; no FPS is inferred.",
      "Axis latency starts at client receipt, not hardware input; GPU execution is not measured.",
      "Scroll sources require complete pointerFrame groups; absent sources or boundaries are unknown. Mixed render-frame sources are reported as mixed.",
    ]
    if axisCoverage["withoutFrameStart"]! > 0 || axisCoverage["withoutSuccessfulSwap"]! > 0 {
      warnings.append(
        "Some axis events have no selected frame start or successful swap; latency samples omit them. Inspect axisEventCoverage and widen a filtered range before diagnosing."
      )
    }
    if axisCoverage["withoutPresentationTime"]! > 0 {
      warnings.append(
        "Some axis events have no selected matching-clock presentation time; presentation latency is incomplete.")
    }
    if failedSwaps > 0 { warnings.append("EGL swaps failed; latency distributions omit failed submissions.") }
    if capture.droppedEvents > 0 {
      warnings.append("Capture saturated: the retained prefix may contain incomplete frames.")
    }
    if metadata["presentationSupported"] as? Bool != true {
      warnings.append("Compositor presentation feedback unavailable.")
    } else if metadata["presentationClockID"] as? Int != 1 {
      warnings.append("Presentation clock differs from CLOCK_MONOTONIC; cross-clock latency omitted.")
    }
    return [
      "units": "milliseconds", "metadata": metadata, "refreshHz": refreshHz, "budget": budget,
      "capturedEvents": selected.count, "failedSwaps": failedSwaps, "droppedEvents": capture.droppedEvents,
      "rangeSeconds": ["start": start, "end": min(end, capture.ended - capture.started)],
      "phaseDurationsInclusive": phases.mapValues { distribution($0, budget: budget) },
      "perFrameInputAndFrameWallUnionByMode": groups.mapValues { distribution($0, budget: budget) },
      "frameIntervalsIncludingIdle": distribution(intervals(starts.map(\.value))),
      "consecutiveFrameIntervalsByMode": modeIntervals.mapValues { distribution($0) },
      "callbackDeliveryIntervalsIncludingIdle": distribution(intervals(callbacks.map(\.start))),
      "callbackProtocolIntervalsIncludingIdle": distribution(protocolIntervals),
      "presentationIntervalsIncludingIdle": distribution(intervals(presentations)),
      "continuousDemandFrameIntervals": distribution(pacing),
      "missedDemandSlots": pacing.reduce(0) { $0 + max(0, floor($1 / budget + 0.5) - 1) },
      "latencies": latencies.mapValues { distribution($0) },
      "plannedSchedulerDelay": distribution(
        selected.filter { $0.phase == "scheduled" }.compactMap { $0.value.map { $0 * 1000 } }),
      "schedulerDeadlineLateness": distribution(
        selected.filter { $0.phase == "schedulerTake" }.compactMap { $0.value.map { $0 * 1000 } }),
      "workInclusive": work, "glCounters": counters, "eventCounts": counts,
      "axisEventCoverage": axisCoverage, "inputWallUnionWithoutFrameStart": distribution(unframedWork, budget: budget),
      "gpuExecution": NSNull(), "warnings": warnings,
    ]
  }
}
