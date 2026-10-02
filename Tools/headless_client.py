#!/usr/bin/env python3
"""Small, dependency-free client for Chroma's version 1 headless JSONL protocol.

Run this file for a demo, or import HeadlessClient from an agent/test harness.
The process is real: stdin and stdout are pipes, stderr is drained independently,
and receiving a response has a deadline. No display server or sleeps are needed.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import queue
import subprocess
import sys
import threading
from typing import Any, Iterable


class ProtocolError(RuntimeError):
    """The process did not produce the expected JSONL response."""


def _reject_constant(value: str) -> None:
    raise ValueError(f"non-JSON number: {value}")


class HeadlessClient:
    """Launch one headless process and exchange ordered requests/responses.

    send_many writes a burst before reading any response. A background reader
    drains stdout so a large frame cannot deadlock the next stdin write.
    """

    def __init__(
        self,
        executable: str | Path,
        *,
        arguments: Iterable[str] = ("--headless",),
        timeout: float = 10.0,
    ) -> None:
        self.timeout = timeout
        self.process = subprocess.Popen(
            [str(Path(executable).resolve()), *arguments],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )
        self._lines: queue.Queue[bytes | None] = queue.Queue()
        self._diagnostics = bytearray()
        self._diagnostics_lock = threading.Lock()
        self._stdout_thread = threading.Thread(target=self._read_stdout, daemon=True)
        self._stderr_thread = threading.Thread(target=self._read_stderr, daemon=True)
        self._stdout_thread.start()
        self._stderr_thread.start()

    def _read_stdout(self) -> None:
        assert self.process.stdout is not None
        try:
            for line in self.process.stdout:
                self._lines.put(line)
        finally:
            self._lines.put(None)

    def _read_stderr(self) -> None:
        assert self.process.stderr is not None
        while chunk := self.process.stderr.read(4096):
            with self._diagnostics_lock:
                self._diagnostics.extend(chunk)
                # Keep diagnostics useful without accumulating unlimited logs.
                del self._diagnostics[:-65536]

    @property
    def diagnostics(self) -> str:
        with self._diagnostics_lock:
            return self._diagnostics.decode("utf-8", errors="replace")

    @staticmethod
    def encode(request: dict[str, Any]) -> bytes:
        return (
            json.dumps(request, separators=(",", ":"), ensure_ascii=False, allow_nan=False)
            + "\n"
        ).encode("utf-8")

    def write_raw(self, data: bytes) -> None:
        assert self.process.stdin is not None
        # Unbuffered pipe writes can be short; preserve all bytes and ordering.
        view = memoryview(data)
        while view:
            count = self.process.stdin.write(view)
            if not count:
                raise ProtocolError("headless stdin stopped accepting input")
            view = view[count:]
        self.process.stdin.flush()

    def send(self, request: dict[str, Any]) -> None:
        self.write_raw(self.encode(request))

    def send_many(self, requests: Iterable[dict[str, Any]]) -> None:
        self.write_raw(b"".join(self.encode(request) for request in requests))

    def _next_line(self) -> bytes | None:
        try:
            return self._lines.get(timeout=self.timeout)
        except queue.Empty as error:
            raise ProtocolError(
                f"no response within {self.timeout:g}s; stderr: {self.diagnostics!r}"
            ) from error

    def receive(self) -> dict[str, Any]:
        line = self._next_line()
        if line is None:
            raise ProtocolError(f"unexpected stdout EOF; stderr: {self.diagnostics!r}")
        if not line.endswith(b"\n"):
            raise ProtocolError(f"response lacks a newline: {line[:200]!r}")
        try:
            response = json.loads(line.decode("utf-8"), parse_constant=_reject_constant)
        except (UnicodeDecodeError, ValueError) as error:
            raise ProtocolError(f"stdout is not JSONL: {line[:200]!r}") from error
        if not isinstance(response, dict):
            raise ProtocolError(f"response is not a JSON object: {response!r}")
        return response

    def request(self, op: str, **fields: Any) -> dict[str, Any]:
        self.send({"version": 1, "op": op, **fields})
        return self.receive()

    def close_input(self) -> None:
        assert self.process.stdin is not None
        if not self.process.stdin.closed:
            self.process.stdin.close()

    def expect_eof(self) -> int:
        """Assert no extra stdout output, then return the child's exit status."""
        line = self._next_line()
        if line is not None:
            raise ProtocolError(f"unexpected extra stdout line: {line[:200]!r}")
        try:
            result = self.process.wait(timeout=self.timeout)
        except subprocess.TimeoutExpired as error:
            raise ProtocolError("process did not exit after closing stdout") from error
        self._stderr_thread.join(timeout=self.timeout)
        return result

    def close(self) -> None:
        self.close_input()
        try:
            self.process.wait(timeout=self.timeout)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=2)
        self._stdout_thread.join(timeout=2)
        self._stderr_thread.join(timeout=2)
        assert self.process.stdout is not None and self.process.stderr is not None
        self.process.stdout.close()
        self.process.stderr.close()

    def __enter__(self) -> HeadlessClient:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


def frame_texts(response: dict[str, Any]) -> list[str]:
    """Extract DrawCommand.text strings from Swift's synthesized Codable shape."""
    return [
        command["text"]["text"]
        for command in response.get("commands", [])
        if "text" in command
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("executable", nargs="?", default=".build/debug/ChromaHeadlessDemo")
    parser.add_argument("--viewport", default="800x600")
    parser.add_argument("--text", default="Hello from a subprocess")
    args = parser.parse_args()
    with HeadlessClient(args.executable, arguments=("--headless", "--viewport", args.viewport)) as client:
        requests = [
            {"version": 1, "id": "initial", "op": "frame"},
            {"version": 1, "id": "focus", "op": "key", "key": "tab"},
            {"version": 1, "id": "edit", "op": "key", "key": "enter"},
            {"version": 1, "id": "type", "op": "key", "text": args.text},
            {"version": 1, "id": "final", "op": "frame"},
            {"version": 1, "id": "quit", "op": "quit"},
        ]
        client.send_many(requests)
        for request in requests:
            response = client.receive()
            if response.get("id") != request["id"]:
                raise ProtocolError(f"out-of-order response: {response!r}")
            expected = "closed" if request["op"] == "quit" else "frame"
            if response.get("status") != expected:
                raise ProtocolError(f"unexpected response: {response!r}")
            # The driver also uses JSONL stdout, so it can feed other tools.
            print(json.dumps(response, separators=(",", ":"), ensure_ascii=False))
        if client.expect_eof() != 0:
            raise ProtocolError(f"process exited unsuccessfully: {client.diagnostics}")
        if client.diagnostics:
            print(client.diagnostics, file=sys.stderr, end="")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ProtocolError) as error:
        print(f"headless client: {error}", file=sys.stderr)
        raise SystemExit(1)
