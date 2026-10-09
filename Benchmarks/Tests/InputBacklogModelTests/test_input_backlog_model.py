import importlib.util
from pathlib import Path
import sys
import unittest

PATH = Path(__file__).resolve().parents[2] / "Scripts" / "input_backlog_model.py"
SPEC = importlib.util.spec_from_file_location("input_backlog_model", PATH)
MODEL = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODEL
SPEC.loader.exec_module(MODEL)


class InputBacklogModelTests(unittest.TestCase):
    def test_saturated_drain_finishes_every_sample_then_recovers(self):
        result = MODEL.simulate(MODEL.Configuration(policy="drain"))
        self.assertEqual(result["applied_samples"], 180)
        self.assertEqual(result["samples_per_frame"], [180])
        self.assertEqual(result["last_frame_start_ns"], 4_140_000_000)
        self.assertEqual(result["recovery_after_source_end_ns"], 1_140_000_000)
        self.assertEqual(result["longest_dispatch_ns"], 4_140_000_000)
        self.assertEqual(result["overdue_ready_wait_ns"], 4_117_000_000)
        self.assertEqual(result["overdue_not_ready_wait_ns"], 0)
        self.assertEqual(result["unrendered_samples"], 0)
        self.assertFalse(result["idle_has_demand"])

    def test_two_axes_double_callback_cost_without_dropping_logical_samples(self):
        result = MODEL.simulate(MODEL.Configuration(policy="drain", axes=2))
        self.assertEqual(result["axis_callbacks"], 360)
        self.assertEqual(result["rendered_samples"], 180)
        self.assertEqual(result["last_frame_start_ns"], 8_280_000_000)

    def test_less_cpu_work_can_eliminate_backlog_without_changing_policy(self):
        result = MODEL.simulate(MODEL.Configuration(policy="drain", cost_ns=2_000_000))
        self.assertEqual(result["recovery_after_source_end_ns"], 0)
        self.assertLessEqual(result["peak_waiting_samples"], 2)
        self.assertGreater(result["active_frames"], 100)

    def test_snapshot_and_sample_boundaries_offer_frames_without_claiming_60hz(self):
        drain = MODEL.simulate(MODEL.Configuration(policy="drain"))
        snapshot = MODEL.simulate(MODEL.Configuration(policy="snapshot"))
        sample = MODEL.simulate(MODEL.Configuration(policy="sample"))
        self.assertGreater(snapshot["active_frames"], drain["active_frames"])
        self.assertGreater(sample["active_frames"], snapshot["active_frames"])
        self.assertEqual(sample["active_frames"], 180)
        self.assertGreater(sample["recovery_after_source_end_ns"], 0)
        # Frame work competes for the same executor and can lengthen recovery.
        self.assertGreater(sample["recovery_after_source_end_ns"], drain["recovery_after_source_end_ns"])

    def test_backpressure_and_ready_wait_are_separate(self):
        result = MODEL.simulate(MODEL.Configuration(
            policy="sample", callback_delay_ns=100_000_000))
        self.assertGreater(result["overdue_not_ready_wait_ns"], 0)
        self.assertGreater(result["overdue_ready_wait_ns"], 0)
        times = result["frame_starts_ns"]
        self.assertTrue(all(b - a >= 101_000_000 for a, b in zip(times, times[1:])))
        self.assertEqual(result["rendered_samples"], 180)

    def test_cap_survives_zero_cost_and_late_frames_without_catch_up_bursts(self):
        for cost in (0, 2_000_000, 65_000_000):
            for policy in ("drain", "snapshot", "sample"):
                with self.subTest(cost=cost, policy=policy):
                    result = MODEL.simulate(MODEL.Configuration(cost_ns=cost, policy=policy))
                    times = [0] + result["frame_starts_ns"]
                    self.assertTrue(all(b - a >= 16_666_667 for a, b in zip(times, times[1:])))
                    self.assertEqual(sum(result["samples_per_frame"]), 180)

    def test_one_sample_and_slow_input_recover_without_extra_idle_frame(self):
        single = MODEL.simulate(MODEL.Configuration(samples=1))
        self.assertEqual(single["active_frames"], 1)
        slow = MODEL.simulate(MODEL.Configuration(samples=3, input_hz=1))
        self.assertEqual(slow["samples_per_frame"], [1, 1, 1])
        self.assertFalse(slow["idle_has_demand"])

    def test_invalid_workloads_fail_instead_of_hanging(self):
        for kwargs in ({"samples": 0}, {"input_hz": 0}, {"maximum_hz": 241},
                       {"cost_ns": -1}, {"axes": 3}, {"policy": "guess"}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                MODEL.simulate(MODEL.Configuration(**kwargs))


if __name__ == "__main__":
    unittest.main()
