#!/usr/bin/env python3
"""Compare identical MissingGlyphBenchmark binaries, preserving every trial."""

import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import tempfile


def trial(binary, scenario):
    args = [str(binary)] + (["--distinct"] if scenario == "distinct-256" else [])
    env = dict(os.environ)
    env.pop("CHROMA_MISSING_GLYPH_WARNINGS", None)
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    with tempfile.TemporaryFile() as stderr:
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=stderr, env=env, check=True, timeout=30)
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        byte_count = stderr.tell()
        stderr.seek(0)
        line_count = sum(1 for _ in stderr)
    fields = dict(field.split("=", 1) for field in result.stdout.decode().strip().split())
    return {
        "scenario": fields["scenario"],
        "lookups": int(fields["lookups"]),
        "lookup_seconds": float(fields["seconds"]),
        "checksum": float(fields["checksum"]),
        "process_cpu_seconds": (after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime),
        "stderr_lines": line_count,
        "stderr_bytes": byte_count,
    }


def blocked_pipe(binary):
    env = dict(os.environ)
    env.pop("CHROMA_MISSING_GLYPH_WARNINGS", None)
    process = subprocess.Popen([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    try:
        process.wait(timeout=2)
        completed = True
    except subprocess.TimeoutExpired:
        completed = False
        process.kill()
        process.wait()
    stdout, stderr = process.communicate()
    return {
        "completed_without_stderr_reader": completed,
        "exit_code": process.returncode,
        "stdout": stdout.decode().strip(),
        "stderr_bytes": len(stderr),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("bounded", type=Path)
    args = parser.parse_args()
    binaries = {"baseline": args.baseline.resolve(), "bounded": args.bounded.resolve()}
    rows = []
    for scenario in ("repeated", "distinct-256"):
        for repeat in range(3):
            order = ("baseline", "bounded") if repeat % 2 == 0 else ("bounded", "baseline")
            for version in order:
                row = trial(binaries[version], scenario)
                row.update(version=version, trial=repeat + 1)
                assert row["lookups"] == 200_000
                expected_lines = 200_000 if version == "baseline" else (1 if scenario == "repeated" else 65)
                assert row["stderr_lines"] == expected_lines, row
                rows.append(row)
    assert len({row["checksum"] for row in rows}) == 1
    result = {
        "trials": rows,
        "blocked_pipe": {version: blocked_pipe(binary) for version, binary in binaries.items()},
    }
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
