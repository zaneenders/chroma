#!/usr/bin/env python3
"""Summarize bounded Chroma native traces; all durations are milliseconds."""
import argparse
import collections
import json
import math

CPU_PHASES = {
    "displayDispatch", "input", "momentumInput", "registrationRefresh",
    "reconciliation", "layoutRegistration", "painting", "frameProduction",
    "frameCPU", "frameObservation", "openGLClear", "openGLSubmission", "eglSwap",
}
WORK_COUNTERS = (
    "bodyEvaluations", "measurements", "measurementCacheHits", "textLayouts",
    "placements", "registrations", "paints", "drawingCommands",
)
SCROLL_PHASES = {"scrollHorizontal", "scrollVertical"}


def distribution(values, budget=None):
    ordered = sorted(values)
    result = {"samples": len(ordered), "p50": None, "p95": None, "max": None}
    if ordered:
        result.update(p50=ordered[(len(ordered) - 1) // 2],
                      p95=ordered[math.ceil(len(ordered) * 0.95) - 1], max=ordered[-1])
    if budget is not None:
        result["overBudget"] = sum(value > budget for value in ordered)
    return result


def union_duration(events):
    intervals = sorted((e["start"], e["end"]) for e in events)
    total = 0
    end = -math.inf
    for start, stop in intervals:
        total += max(0, stop - max(start, end))
        end = max(end, stop)
    return total * 1000


def intervals(values):
    return [1000 * (b - a) for a, b in zip(values, values[1:]) if b >= a]


def summarize(report, refresh_hz=60, start=0, end=math.inf):
    if report["schemaVersion"] != 1 or report["capture"]["clock"] != "CLOCK_MONOTONIC":
        raise ValueError("unsupported trace schema or clock")
    if not math.isfinite(refresh_hz) or not 1 <= refresh_hz <= 1000 or not 0 <= start < end:
        raise ValueError("invalid refresh rate or capture range")
    capture = report["capture"]
    origin = capture["started"]
    events = sorted(capture["events"], key=lambda e: (e["start"], e["end"]))
    for event in events:
        if not math.isfinite(event["start"]) or not math.isfinite(event["end"]) or event["end"] < event["start"]:
            raise ValueError("invalid event duration")
    selected = [e for e in events if start <= e["start"] - origin < end]
    by_frame = collections.defaultdict(list)
    for event in selected:
        by_frame[event["frame"]].append(event)
    budget = 1000 / refresh_hz
    phases = collections.defaultdict(list)
    for event in selected:
        if event["phase"] in CPU_PHASES | {"displayQueue"}:
            phases[event["phase"]].append(1000 * (event["end"] - event["start"]))

    source = "unknown"
    sources = {}
    for event in events:
        if event["phase"] in {"fingerSource", "otherSource"}:
            source = "finger" if event["phase"] == "fingerSource" else "otherSource"
        if event["phase"] in SCROLL_PHASES:
            sources[event["frame"]] = source

    unavailable = []
    blocked_since = origin if any(e["phase"] == "readiness" for e in events) else None
    for event in events:
        if event["phase"] != "readiness":
            continue
        if event["value"] == 0 and blocked_since is None:
            blocked_since = event["start"]
        elif event["value"] == 1 and blocked_since is not None:
            unavailable.append((blocked_since, event["start"]))
            blocked_since = None
    if blocked_since is not None:
        unavailable.append((blocked_since, capture["ended"]))

    frame_starts = {e["frame"]: e["start"] for e in selected if e["phase"] == "frameStart"}
    modes = {}
    groups = collections.defaultdict(list)
    latencies = collections.defaultdict(list)
    for frame, timestamp in sorted(frame_starts.items()):
        current = by_frame[frame]
        names = {e["phase"] for e in current}
        axes = names & SCROLL_PHASES
        if axes:
            direction = "diagonal" if len(axes) == 2 else "horizontal" if "scrollHorizontal" in axes else "vertical"
            mode = sources.get(frame, "unknown") + ":" + direction
        elif "momentumInput" in names:
            mode = "momentum"
        else:
            mode = "other"
        modes[frame] = mode
        cpu = [e for e in current if e["phase"] in {"input", "momentumInput", "frameCPU"}]
        groups[mode].append(union_duration(cpu))
        swap = next((e for e in current if e["phase"] == "eglSwap" and e.get("value", 1) == 1), None)
        callback = next((e for e in current if e["phase"] == "frameCallback"), None)
        presented = next((e.get("presentation") for e in current if e["phase"] == "presented"), None)
        if swap and callback:
            latencies["swapReturnToCallbackDelivery"].append(1000 * (callback["start"] - swap["end"]))
        if swap and presented and presented.get("time") is not None:
            latencies["swapReturnToPresentation"].append(1000 * (presented["time"] - swap["end"]))
        requests = [e["start"] - e["value"] for e in current if e["phase"] == "schedulerDemandAge"]
        if requests and min(requests) <= timestamp:
            requested = min(requests)
            wait = 1000 * (timestamp - requested)
            blocked = 1000 * sum(max(0, min(b, timestamp) - max(a, requested)) for a, b in unavailable)
            latencies["requestToFrameStart"].append(wait)
            latencies["requestWaitWhileNotReady"].append(blocked)
            latencies["requestWaitWhileReady"].append(max(0, wait - blocked))
        for receipt in (e["start"] for e in current if e["phase"] in SCROLL_PHASES):
            if receipt <= timestamp:
                latencies["axisReceiptToFrameStart"].append(1000 * (timestamp - receipt))
            if swap:
                latencies["axisReceiptToSwapReturn"].append(1000 * (swap["end"] - receipt))
            if swap and presented and presented.get("time") is not None:
                latencies["axisReceiptToPresentation"].append(1000 * (presented["time"] - receipt))

    callbacks = sorted((e for e in selected if e["phase"] == "frameCallback"), key=lambda e: e["start"])
    protocol_intervals = [((b["protocolMilliseconds"] - a["protocolMilliseconds"]) & 0xFFFFFFFF)
                          for a, b in zip(callbacks, callbacks[1:])
                          if "protocolMilliseconds" in a and "protocolMilliseconds" in b]
    presentations = sorted((e["presentation"]["clockTime"] for e in selected if e.get("presentation")))
    pacing = []
    starts = sorted(frame_starts.items())
    for (previous, previous_time), (frame, timestamp) in zip(starts, starts[1:]):
        current = by_frame[frame]
        requests = [e["start"] - e["value"] for e in current if e["phase"] == "schedulerDemandAge"]
        requests += [e["start"] for e in current if e["phase"] in SCROLL_PHASES]
        continuously_demanded = (modes[previous] == modes[frame] == "momentum"
                                or any(t <= previous_time + budget / 1000 for t in requests))
        if frame == previous + 1 and continuously_demanded:
            pacing.append(1000 * (timestamp - previous_time))

    work = {}
    for phase in ("input", "momentumInput", "registrationRefresh", "frameProduction"):
        samples = [e["work"] for e in selected if e["phase"] == phase and "work" in e]
        work[phase] = {"calls": len(samples), "totals": {
            key: sum(sample.get(key, 0) for sample in samples) for key in WORK_COUNTERS}}
    counts = collections.Counter(e["phase"] for e in selected)
    failed_swaps = sum(e["phase"] == "eglSwap" and e.get("value") == 0 for e in selected)
    counters = {name: distribution([e["value"] for e in selected if e["phase"] == name and "value" in e])
                for name in ("glInstances", "glDrawCalls", "glUploadCalls", "glUploadBytes")}
    warnings = ["CPU scopes are inclusive wall time (including driver waits); do not add parent and child distributions.",
                "All-frame and callback intervals include deliberate idle gaps; no FPS is inferred.",
                "Axis latency starts at client receipt, not hardware input; GPU execution is not measured."]
    if failed_swaps:
        warnings.append("EGL swaps failed; latency distributions omit failed submissions.")
    if capture["droppedEvents"]:
        warnings.append("Capture saturated: the retained prefix may contain incomplete frames.")
    if not report["metadata"].get("presentationSupported"):
        warnings.append("Compositor presentation feedback unavailable.")
    elif report["metadata"].get("presentationClockID") != 1:
        warnings.append("Presentation clock differs from CLOCK_MONOTONIC; cross-clock latency omitted.")
    return {
        "units": "milliseconds", "metadata": report["metadata"], "refreshHz": refresh_hz,
        "budget": budget, "capturedEvents": len(selected), "failedSwaps": failed_swaps, "droppedEvents": capture["droppedEvents"],
        "rangeSeconds": {"start": start, "end": min(end, capture["ended"] - origin)},
        "phaseDurationsInclusive": {name: distribution(values, budget) for name, values in sorted(phases.items())},
        "perFrameInputAndFrameWallUnionByMode": {mode: distribution(values, budget) for mode, values in sorted(groups.items())},
        "frameIntervalsIncludingIdle": distribution(intervals([t for _, t in starts])),
        "callbackDeliveryIntervalsIncludingIdle": distribution(intervals([e["start"] for e in callbacks])),
        "callbackProtocolIntervalsIncludingIdle": distribution(protocol_intervals),
        "presentationIntervalsIncludingIdle": distribution(intervals(presentations)),
        "continuousDemandFrameIntervals": distribution(pacing),
        "missedDemandSlots": sum(max(0, math.floor(value / budget + 0.5) - 1) for value in pacing),
        "latencies": {name: distribution(values) for name, values in sorted(latencies.items())},
        "plannedSchedulerDelay": distribution([e["value"] * 1000 for e in selected if e["phase"] == "scheduled"]),
        "schedulerDeadlineLateness": distribution([e["value"] * 1000 for e in selected if e["phase"] == "schedulerTake"]),
        "workInclusive": work, "glCounters": counters, "eventCounts": dict(sorted(counts.items())),
        "gpuExecution": None, "warnings": warnings,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace")
    parser.add_argument("--refresh-hz", type=float, default=60)
    parser.add_argument("--start", type=float, default=0, help="seconds from capture start")
    parser.add_argument("--end", type=float, default=math.inf)
    args = parser.parse_args()
    try:
        with open(args.trace, encoding="utf-8") as trace:
            report = summarize(json.load(trace), args.refresh_hz, args.start, args.end)
        print(json.dumps(report, indent=2, sort_keys=True, allow_nan=False))
    except (ValueError, KeyError, OSError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
