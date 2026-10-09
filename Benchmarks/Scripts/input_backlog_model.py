#!/usr/bin/env python3
"""Deterministic queueing experiment, NOT a native latency measurement.

All arithmetic uses integer nanoseconds. Policies are explicit hypothetical
executor opportunities, not a claim about libwayland batching or Swift fairness.
"""

import argparse
from collections import deque
from dataclasses import dataclass
import json
import math

SECOND = 1_000_000_000


@dataclass(frozen=True)
class Configuration:
    samples: int = 180
    input_hz: int = 60
    axes: int = 1
    cost_ns: int = 23_000_000  # per axis callback, not per logical sample
    frame_cost_ns: int = 1_000_000
    maximum_hz: int = 60
    callback_delay_ns: int = 0
    policy: str = "snapshot"

    def validate(self):
        for value in (self.samples, self.input_hz, self.axes, self.maximum_hz):
            if type(value) is not int or value <= 0:
                raise ValueError("counts and rates must be positive integers")
        if self.axes not in (1, 2) or self.samples > 1_000_000:
            raise ValueError("axes must be 1 or 2; samples must be <= 1000000")
        for value in (self.cost_ns, self.frame_cost_ns, self.callback_delay_ns):
            if type(value) is not int or value < 0:
                raise ValueError("costs must be nonnegative integer nanoseconds")
        if self.input_hz > SECOND or self.maximum_hz > 240:
            raise ValueError("input rate is too high or frame cap exceeds 240 Hz")
        if self.policy not in ("drain", "snapshot", "sample"):
            raise ValueError("unknown dispatch policy")


def percentile(values, quantile):
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(len(ordered) * quantile) - 1)]


def simulate(config):
    config.validate()
    # Initial frame at t=0 is excluded from active frame and latency samples.
    now = 0
    last_frame = 0
    ready_at = 0
    source_index = 0
    queue = deque()
    pending = []
    applied = []
    frame_times = []
    frame_samples = []
    completion_latencies = []
    rendered_latencies = []
    peak_queue = 0
    demand_since = None
    ready_blocked_ns = 0
    not_ready_ns = 0
    batches = []

    def arrival(index):
        return index * SECOND // config.input_hz

    # Ceiling preserves the maximum-rate cap even for nonintegral periods.
    frame_period = (SECOND + config.maximum_hz - 1) // config.maximum_hz

    def collect():
        nonlocal source_index, peak_queue
        while source_index < config.samples and arrival(source_index) <= now:
            queue.append(source_index)
            source_index += 1
        peak_queue = max(peak_queue, len(queue))

    def advance(until):
        nonlocal now, ready_blocked_ns, not_ready_ns
        assert until >= now
        if demand_since is not None:
            eligible = max(now, last_frame + frame_period, demand_since)
            # These partition overdue demand time, excluding cap-imposed wait.
            not_ready_ns += max(0, min(until, ready_at) - eligible)
            ready_blocked_ns += max(0, until - max(eligible, ready_at))
        now = until

    while source_index < config.samples or queue or pending:
        collect()
        # Explicit frame opportunity at a completed dispatch boundary. This is
        # an assumption under comparison, not Task.yield() or production code.
        if pending and now >= max(ready_at, last_frame + frame_period):
            frame_times.append(now)
            frame_samples.append(list(pending))
            rendered_latencies.extend(now - arrival(index) for index in pending)
            pending.clear()
            demand_since = None
            last_frame = now
            advance(now + config.frame_cost_ns)
            ready_at = now + config.callback_delay_ns
            continue
        if queue:
            batch_start = now
            count = 0
            limit = 1 if config.policy == "sample" else len(queue)
            while queue and (config.policy == "drain" or count < limit):
                index = queue.popleft()
                advance(now + config.axes * config.cost_ns)
                applied.append(index)
                completion_latencies.append(now - arrival(index))
                pending.append(index)
                if demand_since is None:
                    demand_since = now
                count += 1
                collect()
            batches.append({"start_ns": batch_start, "end_ns": now, "samples": count})
            continue
        candidates = []
        if source_index < config.samples:
            candidates.append(arrival(source_index))
        if pending:
            candidates.append(max(ready_at, last_frame + frame_period))
        advance(min(candidates))

    assert applied == list(range(config.samples))
    assert [index for group in frame_samples for index in group] == applied
    assert all(b - a >= frame_period for a, b in zip([0] + frame_times, frame_times))
    return {
        "schema_version": 1,
        "kind": "deterministic_model_not_native_measurement",
        "configuration": vars(config),
        "applied_samples": len(applied),
        "axis_callbacks": len(applied) * config.axes,
        "rendered_samples": sum(map(len, frame_samples)),
        "unrendered_samples": len(pending),
        "active_frames": len(frame_times),
        "peak_waiting_samples": peak_queue,
        "source_end_ns": arrival(config.samples),
        "last_sample_arrival_ns": arrival(config.samples - 1),
        "last_frame_start_ns": frame_times[-1],
        "recovery_after_source_end_ns": max(0, frame_times[-1] - arrival(config.samples)),
        "input_completion_latency_p50_ns": percentile(completion_latencies, 0.5),
        "input_completion_latency_p95_ns": percentile(completion_latencies, 0.95),
        "arrival_to_frame_p50_ns": percentile(rendered_latencies, 0.5),
        "arrival_to_frame_p95_ns": percentile(rendered_latencies, 0.95),
        "overdue_ready_wait_ns": ready_blocked_ns,
        "overdue_not_ready_wait_ns": not_ready_ns,
        "longest_dispatch_ns": max(batch["end_ns"] - batch["start_ns"] for batch in batches),
        "frame_starts_ns": frame_times,
        "samples_per_frame": list(map(len, frame_samples)),
        "dispatch_batches": batches,
        "idle_has_demand": bool(pending),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", type=int, default=180)
    parser.add_argument("--input-hz", type=int, default=60)
    parser.add_argument("--axes", type=int, choices=(1, 2), default=1)
    parser.add_argument("--input-cost-us", type=int, default=23000)
    parser.add_argument("--frame-cost-us", type=int, default=1000)
    parser.add_argument("--callback-delay-us", type=int, default=0)
    parser.add_argument("--maximum-hz", type=int, default=60)
    parser.add_argument("--policy", choices=("drain", "snapshot", "sample"), default="snapshot")
    args = parser.parse_args()
    config = Configuration(
        samples=args.samples, input_hz=args.input_hz, axes=args.axes,
        cost_ns=args.input_cost_us * 1000, frame_cost_ns=args.frame_cost_us * 1000,
        maximum_hz=args.maximum_hz, callback_delay_ns=args.callback_delay_us * 1000,
        policy=args.policy,
    )
    try:
        result = simulate(config)
    except ValueError as error:
        parser.error(str(error))
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
