#!/usr/bin/env python3
"""Real-pipe integration tests: python3 Tools/test_headless_stdio.py [executable]."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import unittest

from headless_client import HeadlessClient, frame_texts


class HeadlessStdioTests(unittest.TestCase):
    executable = Path(".build/debug/ChromaHeadlessDemo")
    timeout = 10.0

    def client(self, *arguments: str) -> HeadlessClient:
        client = HeadlessClient(
            self.executable, arguments=arguments or ("--headless",), timeout=self.timeout
        )
        self.addCleanup(client.close)
        return client

    def assert_frame(self, response: dict, request_id: str | None = None) -> None:
        self.assertEqual(response.get("version"), 1)
        self.assertEqual(response.get("status"), "frame", response)
        self.assertIsInstance(response.get("commands"), list)
        self.assertIsInstance(response.get("viewport"), dict)
        self.assertNotIn("error", response)
        if request_id is not None:
            self.assertEqual(response.get("id"), request_id)
        # Refuse NaN/Infinity even when nested in draw commands.
        json.dumps(response, allow_nan=False)

    def assert_error(self, response: dict) -> None:
        self.assertEqual(response.get("version"), 1)
        self.assertEqual(response.get("status"), "error", response)
        self.assertIsInstance(response.get("error"), str)
        self.assertTrue(response["error"])

    def assert_closed(self, client: HeadlessClient, request_id: str = "quit") -> None:
        response = client.request("quit", id=request_id)
        self.assertEqual(response.get("version"), 1)
        self.assertEqual(response.get("id"), request_id)
        self.assertEqual(response.get("status"), "closed", response)
        self.assertEqual(client.expect_eof(), 0)

    def test_explicit_frames_are_deterministic_and_default_viewport(self) -> None:
        client = self.client()
        first = client.request("frame", id="first")
        self.assert_frame(first, "first")
        self.assertTrue(first["commands"])
        self.assertEqual(first["viewport"], {"width": 800, "height": 600})
        second = client.request("frame", id="second")
        self.assert_frame(second, "second")
        self.assertEqual(first["commands"], second["commands"])
        self.assertIn("First", frame_texts(first))
        self.assertIn("Second", frame_texts(first))
        self.assertIn("Count: 0", frame_texts(first))
        self.assert_closed(client)

    def test_burst_text_tab_text_preserves_order_and_target(self) -> None:
        client = self.client()
        operations = [
            ("frame", {}),
            ("key", {"key": "tab"}),
            ("key", {"key": "enter"}),
            ("key", {"text": "Alpha"}),
            ("key", {"key": "tab"}),
            ("key", {"key": "enter"}),
            ("key", {"text": "Beta"}),
            ("frame", {}),
        ]
        client.send_many(
            {"version": 1, "id": str(i), "op": op, **fields}
            for i, (op, fields) in enumerate(operations)
        )
        responses = [client.receive() for _ in operations]
        for i, response in enumerate(responses):
            self.assert_frame(response, str(i))
        self.assertIn("Alpha", frame_texts(responses[3]))
        self.assertIn("Alpha", frame_texts(responses[-1]))
        self.assertIn("Beta", frame_texts(responses[-1]))
        self.assertNotIn("AlphaBeta", frame_texts(responses[-1]))
        self.assertTrue(responses[3]["focus"]["editing"])
        self.assertEqual(responses[3]["focus"]["caretOffset"], 5)
        self.assertTrue(responses[-1]["focus"]["editing"])
        self.assertEqual(responses[-1]["focus"]["caretOffset"], 4)
        self.assertNotEqual(responses[3]["focus"]["path"], responses[-1]["focus"]["path"])
        self.assert_closed(client)

    def test_repeated_keys_are_not_coalesced(self) -> None:
        client = self.client()
        operations = [
            ("key", {"key": "tab"}),
            ("key", {"key": "enter"}),
            *[("key", {"key": "a", "text": "a"}) for _ in range(12)],
            *[("key", {"key": "backspace"}) for _ in range(5)],
            ("key", {"text": "Z"}),
        ]
        client.send_many(
            {"version": 1, "id": str(i), "op": op, **fields}
            for i, (op, fields) in enumerate(operations)
        )
        responses = [client.receive() for _ in operations]
        for i, response in enumerate(responses):
            self.assert_frame(response, str(i))
        self.assertIn("a" * 12, frame_texts(responses[13]))
        self.assertIn("a" * 7 + "Z", frame_texts(responses[-1]))
        self.assert_closed(client)

    @staticmethod
    def text_position(frame: dict, text: str) -> dict:
        return next(command["text"]["position"] for command in frame["commands"]
                    if command.get("text", {}).get("text") == text)

    def click(self, client: HeadlessClient, position: dict) -> dict:
        # Use the rendered text origin, slightly inset into its first glyph.
        point = {"x": position["x"] + 2, "y": position["y"] + 2}
        for phase in ("move", "down", "up"):
            response = client.request("pointer", phase=phase, **point)
            self.assert_frame(response)
        return response

    def test_pointer_edits_distinct_controls_and_activates_button(self) -> None:
        client = self.client()
        initial = client.request("frame")
        self.assert_frame(initial)
        first = self.text_position(initial, "First")
        second = self.text_position(initial, "Second")
        button = self.text_position(initial, "Count: 0")
        self.click(client, first)
        typed = client.request("key", text="Pointer one")
        self.assertIn("Pointer one", frame_texts(typed))
        self.click(client, second)
        typed = client.request("key", text="Pointer two")
        self.assertIn("Pointer one", frame_texts(typed))
        self.assertIn("Pointer two", frame_texts(typed))
        clicked = self.click(client, button)
        self.assertIn("Count: 1", frame_texts(clicked))
        self.assertIn("Count: 2", frame_texts(self.click(client, button)))
        self.assert_closed(client)

    def test_resize_scroll_and_initial_cli_viewport(self) -> None:
        client = self.client("--headless", "--viewport", "640x480")
        initial = client.request("frame")
        self.assert_frame(initial)
        self.assertEqual(initial["viewport"], {"width": 640, "height": 480})
        for width, height in ((1024, 768), (1, 1), (16384, 16384), (800, 600)):
            response = client.request("resize", width=width, height=height)
            self.assert_frame(response)
            self.assertEqual(response["viewport"], {"width": width, "height": height})
        self.assert_frame(client.request("scroll", x=0, y=-24))
        self.assert_frame(client.request("scroll", x=12, y=0))
        self.assert_closed(client)

    def test_invalid_requests_recover_without_changing_viewport(self) -> None:
        client = self.client()
        invalid = [
            {"version": 2, "op": "frame"},
            {"op": "frame"},
            {"version": "1", "op": "frame"},
            {"version": 1, "op": "unknown"},
            {"version": 1, "op": "resize", "width": 0, "height": 600},
            {"version": 1, "op": "resize", "width": -1, "height": 600},
            {"version": 1, "op": "resize", "width": 16385, "height": 600},
            {"version": 1, "op": "resize", "width": 800, "height": 16385},
            {"version": 1, "op": "resize", "width": "800", "height": 600},
            {"version": 1, "op": "resize", "width": 800},
            {"version": 1, "op": "pointer", "phase": "down", "x": 1000001, "y": 0},
            {"version": 1, "op": "pointer", "phase": "down", "x": 0, "y": -1000001},
            {"version": 1, "op": "pointer", "phase": "bogus", "x": 0, "y": 0},
            {"version": 1, "op": "pointer", "phase": "move", "x": 0},
            {"version": 1, "op": "scroll", "x": 0, "y": 1000001},
            {"version": 1, "op": "key", "key": "not-a-key"},
            {"version": 1, "op": "key", "key": "a", "modifiers": ["unknown"]},
            {"version": 1, "op": "key", "text": "x" * 16385},
            {"version": 1, "op": "key", "text": "é" * 8193},
            {"version": 1, "op": "frame", "id": "i" * 257},
            {"version": 1, "op": "frame", "id": "é" * 129},
        ]
        for i, request in enumerate(invalid):
            with self.subTest(request=i):
                client.send(request)
                self.assert_error(client.receive())
                recovered = client.request("frame", id=f"recover-{i}")
                self.assert_frame(recovered, f"recover-{i}")
                self.assertEqual(recovered["viewport"], {"width": 800, "height": 600})
        self.assert_closed(client)
        self.assertTrue(client.diagnostics, "protocol diagnostics must use stderr")

    def test_malformed_nonfinite_and_invalid_utf8_recover(self) -> None:
        client = self.client()
        malformed = [
            b"not json\n",
            b"{\n",
            b"[]\n",
            b"null\n",
            b"\xff\n",
            b'{"version":1,"op":"resize","width":1e999,"height":600}\n',
            b'{"version":1,"op":"resize","width":NaN,"height":600}\n',
            b'{"version":1,"op":"pointer","phase":"down","x":Infinity,"y":0}\n',
            b'{"version":1,"op":"scroll","x":0,"y":-Infinity}\n',
        ]
        for i, line in enumerate(malformed):
            with self.subTest(line=line):
                client.write_raw(line + HeadlessClient.encode(
                    {"version": 1, "id": f"valid-{i}", "op": "frame"}
                ))
                self.assert_error(client.receive())
                self.assert_frame(client.receive(), f"valid-{i}")
        self.assert_closed(client)

    def test_oversized_line_is_drained_once_and_next_request_recovers(self) -> None:
        client = self.client()
        client.write_raw(b"x" * 200000 + b"\n" + HeadlessClient.encode(
            {"version": 1, "id": "after-large-line", "op": "frame"}
        ))
        self.assert_error(client.receive())
        self.assert_frame(client.receive(), "after-large-line")
        self.assert_closed(client)

    def test_line_size_boundary_and_crlf(self) -> None:
        client = self.client()
        base = b'{"version":1,"id":"boundary","op":"frame"}'
        client.write_raw(base + b" " * (65536 - len(base)) + b"\n")
        self.assert_frame(client.receive(), "boundary")
        client.write_raw(base + b" " * (65537 - len(base)) + b"\n")
        self.assert_error(client.receive())
        client.write_raw(b'{"version":1,"id":"crlf","op":"frame"}\r\n')
        self.assert_frame(client.receive(), "crlf")
        self.assert_closed(client)

    def test_valid_utf8_byte_limits_and_character_selection(self) -> None:
        client = self.client()
        self.assert_frame(client.request("frame", id="é" * 128), "é" * 128)
        client.request("key", key="tab")
        client.request("key", key="enter")
        text = "A👩‍💻e\u0301"
        response = client.request("key", text=text)
        self.assert_frame(response)
        self.assertIn(text, frame_texts(response))
        self.assertEqual(response["focus"]["caretOffset"], 3)
        response = client.request("key", key="left", modifiers=["shift"])
        self.assert_frame(response)
        self.assertEqual(response["focus"]["selectionStart"], 2)
        self.assertEqual(response["focus"]["selectionEnd"], 3)
        self.assert_frame(client.request("key", text="é" * 8192))
        self.assert_closed(client)

    def test_invalid_pointer_transition_preserves_held_state(self) -> None:
        client = self.client()
        initial = client.request("frame")
        point = self.text_position(initial, "Count: 0")
        self.assert_error(client.request("pointer", phase="up", **point))
        self.assert_frame(client.request("pointer", phase="down", **point))
        self.assert_error(client.request("pointer", phase="down", **point))
        released = client.request("pointer", phase="up", **point)
        self.assert_frame(released)
        self.assertIn("Count: 1", frame_texts(released))
        self.assert_closed(client)

    def test_eof_without_requests_exits_without_unsolicited_stdout(self) -> None:
        client = self.client()
        client.close_input()
        self.assertEqual(client.expect_eof(), 0)

    def test_eof_accepts_final_request_without_newline(self) -> None:
        client = self.client()
        client.write_raw(b'{"version":1,"id":"last","op":"frame"}')
        client.close_input()
        self.assert_frame(client.receive(), "last")
        self.assertEqual(client.expect_eof(), 0)

    def test_eof_reports_partial_malformed_request_then_exits(self) -> None:
        client = self.client()
        client.write_raw(b'{"version":1,"op":')
        client.close_input()
        self.assert_error(client.receive())
        self.assertEqual(client.expect_eof(), 0)

    def test_eof_drains_oversized_unterminated_request(self) -> None:
        client = self.client()
        client.write_raw(b"x" * 100000)
        client.close_input()
        self.assert_error(client.receive())
        self.assertEqual(client.expect_eof(), 0)

    def test_quit_ignores_later_buffered_requests(self) -> None:
        client = self.client()
        client.send_many([
            {"version": 1, "id": "quit", "op": "quit"},
            {"version": 1, "id": "ignored", "op": "frame"},
        ])
        response = client.receive()
        self.assertEqual(response.get("status"), "closed")
        self.assertEqual(response.get("id"), "quit")
        self.assertEqual(client.expect_eof(), 0)

    def test_executable_defaults_to_headless_without_flag(self) -> None:
        client = HeadlessClient(self.executable, arguments=(), timeout=self.timeout)
        self.addCleanup(client.close)
        self.assert_frame(client.request("frame"))
        self.assert_closed(client)

    def test_invalid_cli_arguments_exit_nonzero_on_stderr_only(self) -> None:
        for arguments in (
            ["--bogus"], ["--viewport"], ["--viewport", "800"],
            ["--viewport", "0x600"], ["--viewport", "-1x600"],
            ["--viewport", "16385x600"], ["--viewport", "NaNx600"],
            ["--viewport", "800xInfinity"],
        ):
            with self.subTest(arguments=arguments):
                result = subprocess.run(
                    [str(self.executable), *arguments], input=b"", capture_output=True,
                    timeout=self.timeout, check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
                self.assertTrue(result.stderr)

    def test_no_display_environment_is_required(self) -> None:
        environment = dict(os.environ)
        for variable in ("DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR"):
            environment.pop(variable, None)
        result = subprocess.run(
            [str(self.executable), "--headless"],
            input=HeadlessClient.encode({"version": 1, "op": "frame"}),
            capture_output=True, env=environment, timeout=self.timeout, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertEqual(len(lines), 1)
        self.assert_frame(json.loads(lines[0]))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", nargs="?", default=".build/debug/ChromaHeadlessDemo")
    parser.add_argument("--timeout", type=float, default=10.0)
    args, unittest_args = parser.parse_known_args()
    HeadlessStdioTests.executable = Path(args.executable).resolve()
    HeadlessStdioTests.timeout = args.timeout
    if not HeadlessStdioTests.executable.is_file():
        parser.error(f"executable not found: {HeadlessStdioTests.executable}; build ChromaHeadlessDemo first")
    unittest.main(argv=[__file__, *unittest_args], verbosity=2)


if __name__ == "__main__":
    main()
