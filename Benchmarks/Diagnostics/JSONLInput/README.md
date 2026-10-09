# JSONL input transport probe

Run from the repository root, with a Swift 6.4 toolchain:

```sh
sh Benchmarks/Scripts/jsonl-input.sh > current.jsonl
sh Benchmarks/Scripts/jsonl-input.sh /path/to/baseline-checkout > baseline.jsonl
```

The script compiles this same driver with the selected checkout's actual
`Sources/ChromaHeadless/BoundedLineReader.swift`, using `swiftc -O -swift-version 6 -warnings-as-errors`. It does not add
an exported production API or a package dependency. Use the same machine/toolchain
and idle competing builds/benchmarks for comparisons.

Each workload uses a real pipe and concurrent producer. Short bursts send 10,000
43-byte frame requests, handshakes send 1,000 and wait for the reader to consume each
line before writing the next, maximum-length requests send 32 lines of 65,536 bytes,
and oversized discard sends eight lines of 262,144 bytes. Sizes exclude the LF.
The driver validates every returned line/status and EOF. One warmup per workload is
omitted, followed by five printed samples. Each sample creates a fresh pipe/reader;
construction and payload assembly are outside timing. Timing includes producer
scheduling, pipe writes/reads, line comparison and EOF, excluding teardown.

This measures transport framing only. It excludes JSON decoding, detached-task
scheduling in HeadlessSession, input application, rendering and response encoding.
It does not measure native/GPU frame latency or imply equivalent end-to-end gains.
There are no wall-clock pass/fail thresholds. Handshake timeouts are deadlock guards.

The production reader uses one 4,096-byte buffer and retains at most
`HeadlessSession.maximumLineBytes` bytes of the current line. After exceeding the
limit it scans/discards chunks through LF, preserving the remainder for the next
request. One POSIX read accepts short input immediately rather than waiting to fill
a chunk. A mutex serializes access to the buffer and file handle; the session still
awaits exactly one detached read at a time and handles requests in order. The read
retries EINTR and propagates other POSIX errors. EOF is remembered after delivering
an optional final unterminated line. LF remains the only delimiter; carriage returns
and Unicode separators remain payload bytes.

Validation lives in `BoundedLineReaderTests` and the separate `HeadlessModeTests`
package, including open-stdin handshakes, partial lines, read-boundary/max-size
requests, oversized/invalid-UTF8 recovery, bursts, EOF and child cancellation/reaping.
EOF and cancellation semantics of the surrounding session/driver are unchanged.
EOF of a regular input stream is terminal for this reader, as it is for the session.
