#!/usr/bin/env python3
"""Verify process logging and main-actor liveness using HeadlessProcessFixture."""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import time
import unittest

from headless_client import HeadlessClient, frame_texts


class HeadlessProcessTests(unittest.TestCase):
    executable: Path

    def client(self) -> HeadlessClient:
        client = HeadlessClient(self.executable, timeout=10)
        self.addCleanup(client.close)
        return client

    def test_logs_stay_on_stderr_and_async_work_progresses_while_stdin_idle(self) -> None:
        client = self.client()
        frame = client.request("frame", id="initial")
        self.assertEqual(frame["id"], "initial")
        self.assertIn("idle", frame_texts(frame))
        position = next(command["text"]["position"] for command in frame["commands"]
                        if command.get("text", {}).get("text") == "Start async")
        for phase in ("down", "up"):
            response = client.request("pointer", phase=phase,
                                      x=position["x"] + 2, y=position["y"] + 2)
            self.assertEqual(response["status"], "frame", response)

        # No more requests until the task has completed. A synchronous stdin
        # read on the main actor would prevent the marker from ever arriving.
        deadline = time.monotonic() + client.timeout
        while "fixture: async complete\n" not in client.diagnostics:
            if time.monotonic() >= deadline:
                self.fail("main-actor work stalled while stdin was idle: " + client.diagnostics)
            time.sleep(0.01)

        completed = client.request("frame", id="after-async")
        self.assertEqual(completed["id"], "after-async")
        self.assertIn("complete", frame_texts(completed))
        self.assertEqual(client.request("quit", id="quit")["status"], "closed")
        self.assertEqual(client.expect_eof(), 0)
        for marker in ("initializer print", "frame observer print", "button callback print",
                       "async print", "model deinit print"):
            self.assertIn("fixture: " + marker, client.diagnostics)

    def test_eof_exits_cleanly_and_flushes_application_logs(self) -> None:
        client = self.client()
        self.assertEqual(client.request("frame")["status"], "frame")
        client.close_input()
        self.assertEqual(client.expect_eof(), 0)
        self.assertIn("fixture: initializer print", client.diagnostics)
        self.assertIn("fixture: frame observer print", client.diagnostics)
        self.assertIn("fixture: model deinit print", client.diagnostics)

    def test_broken_stdout_reports_io_failure_instead_of_sigpipe(self) -> None:
        process = subprocess.Popen([str(self.executable.resolve()), "--headless"],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        assert process.stdin is not None and process.stdout is not None and process.stderr is not None
        try:
            # Close the only stdout reader before the first protocol response.
            process.stdout.close()
            process.stdin.write(b'{"version":1,"op":"frame"}\n')
            process.stdin.flush()
            self.assertEqual(process.wait(timeout=10), 1)
            self.assertIn(b"chroma-headless:", process.stderr.read())
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=10)
            process.stdin.close()
            process.stderr.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", type=Path)
    args, remaining = parser.parse_known_args()
    HeadlessProcessTests.executable = args.executable
    unittest.main(argv=[__file__, *remaining])
