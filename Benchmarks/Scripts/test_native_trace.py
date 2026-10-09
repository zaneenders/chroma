import unittest

from native_trace import distribution, summarize, union_duration


def event(phase, start, end=None, frame=1, **fields):
    return dict(phase=phase, start=start, end=start if end is None else end, frame=frame, **fields)


def report(events, dropped=0, clock_id=1):
    return {"schemaVersion": 1, "metadata": {"presentationSupported": True, "presentationClockID": clock_id},
            "capture": {"clock": "CLOCK_MONOTONIC", "started": 0, "ended": 10,
                        "capacity": 100, "droppedEvents": dropped, "events": events}}


class NativeTraceTests(unittest.TestCase):
    def test_percentiles_and_strict_budget(self):
        self.assertEqual(distribution([1, 2, 3, 4], 3),
                         {"samples": 4, "p50": 2, "p95": 4, "max": 4, "overBudget": 1})
        self.assertIsNone(distribution([])["p95"])

    def test_nested_cpu_scopes_are_not_added(self):
        spans = [event("input", 0, 0.005), event("registrationRefresh", 0, 0.004),
                 event("input", 0.005, 0.009), event("frameCPU", 0.01, 0.015)]
        self.assertAlmostEqual(union_duration(spans), 14)
        result = summarize(report(spans + [event("frameStart", 0.01)]))
        self.assertAlmostEqual(result["perFrameInputAndFrameWallUnionByMode"]["other"]["p50"], 14)
        self.assertEqual(result["phaseDurationsInclusive"]["registrationRefresh"]["samples"], 1)

    def test_diagonal_input_correlates_to_presentation_not_callback(self):
        events = [event("fingerSource", 0), event("scrollVertical", 0.001),
                  event("scrollHorizontal", 0.002), event("input", 0.001, 0.003),
                  event("frameStart", 0.01), event("frameCPU", 0.01, 0.012),
                  event("eglSwap", 0.011, 0.012), event("frameCallback", 0.018, protocolMilliseconds=5),
                  event("presented", 0.025, presentation={"time": 0.020, "clockTime": 0.020})]
        result = summarize(report(events))
        self.assertIn("finger:diagonal", result["perFrameInputAndFrameWallUnionByMode"])
        self.assertAlmostEqual(result["latencies"]["axisReceiptToPresentation"]["p50"], 18)
        self.assertAlmostEqual(result["latencies"]["swapReturnToCallbackDelivery"]["p50"], 6)
        self.assertAlmostEqual(result["latencies"]["swapReturnToPresentation"]["p50"], 8)

    def test_input_flushed_after_frame_start_still_has_presentation_latency(self):
        events = [event("frameStart", 0.01), event("scrollVertical", 0.011),
                  event("eglSwap", 0.012, 0.013, value=1),
                  event("presented", 0.025, presentation={"time": 0.020, "clockTime": 0.020})]
        result = summarize(report(events))
        self.assertNotIn("axisReceiptToFrameStart", result["latencies"])
        self.assertAlmostEqual(result["latencies"]["axisReceiptToPresentation"]["p50"], 9)
        events[2]["value"] = 0
        result = summarize(report(events))
        self.assertEqual(result["failedSwaps"], 1)
        self.assertNotIn("axisReceiptToSwapReturn", result["latencies"])

    def test_unknown_clock_excludes_cross_clock_latency_but_keeps_intervals(self):
        events = [event("frameStart", 0), event("eglSwap", 0, 0.001),
                  event("presented", 0.01, presentation={"clockTime": 123}),
                  event("presented", 0.02, frame=2, presentation={"clockTime": 123.02})]
        result = summarize(report(events, clock_id=0))
        self.assertNotIn("swapReturnToPresentation", result["latencies"])
        self.assertAlmostEqual(result["presentationIntervalsIncludingIdle"]["p50"], 20)
        self.assertTrue(any("clock differs" in warning for warning in result["warnings"]))

    def test_protocol_wrap_idle_gaps_and_missed_demand_slots(self):
        events = [event("frameStart", 0), event("frameCallback", 0.010, protocolMilliseconds=0xFFFFFFFC),
                  event("scrollVertical", 0.015, frame=2), event("frameStart", 0.050, frame=2),
                  event("frameCallback", 0.060, frame=2, protocolMilliseconds=6),
                  event("frameRequested", 4.9, frame=3), event("frameStart", 5, frame=3)]
        result = summarize(report(events))
        self.assertEqual(result["continuousDemandFrameIntervals"]["samples"], 1)
        self.assertEqual(result["missedDemandSlots"], 2)
        self.assertEqual(result["callbackProtocolIntervalsIncludingIdle"]["p50"], 10)
        self.assertEqual(result["frameIntervalsIncludingIdle"]["samples"], 2)

    def test_readiness_wait_is_separate_from_ready_scheduler_wait(self):
        events = [event("readiness", 0, value=1), event("readiness", 0.01, value=0),
                  event("readiness", 0.025, value=1),
                  event("schedulerDemandAge", 0.03, value=0.01), event("frameStart", 0.03)]
        result = summarize(report(events))
        self.assertAlmostEqual(result["latencies"]["requestWaitWhileNotReady"]["p50"], 5)
        self.assertAlmostEqual(result["latencies"]["requestWaitWhileReady"]["p50"], 5)
        self.assertAlmostEqual(result["latencies"]["requestToFrameStart"]["p50"], 10)

    def test_counter_totals_do_not_add_nested_registration(self):
        work = {"bodyEvaluations": 5, "registrations": 9}
        result = summarize(report([event("input", 0, 0.001, work=work),
                                   event("registrationRefresh", 0, 0.001, work=work)]))
        self.assertEqual(result["workInclusive"]["input"]["totals"]["bodyEvaluations"], 5)
        self.assertEqual(result["workInclusive"]["registrationRefresh"]["totals"]["bodyEvaluations"], 5)

    def test_empty_and_saturated_captures_and_selected_ranges(self):
        result = summarize(report([], dropped=1))
        self.assertIsNone(result["frameIntervalsIncludingIdle"]["p50"])
        self.assertTrue(any("saturated" in warning for warning in result["warnings"]))
        result = summarize(report([event("frameStart", 1), event("frameStart", 2, frame=2)]), start=2, end=3)
        self.assertEqual(result["capturedEvents"], 1)
        self.assertEqual(result["frameIntervalsIncludingIdle"]["samples"], 0)

    def test_invalid_timings_or_refresh_rates_are_rejected(self):
        with self.assertRaises(ValueError):
            summarize(report([event("input", 1, 0)]))
        with self.assertRaises(ValueError):
            summarize(report([]), refresh_hz=float("nan"))


if __name__ == "__main__":
    unittest.main()
