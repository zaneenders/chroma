# Headless agents over standard input/output

Chroma applications can run as a subprocess controlled by newline-delimited JSON
(JSONL). The host uses the real `App`, `WindowRuntime`, input routing, layout, and
`DrawCommand` rendering pipeline. It does not create a native window, connect to a
display server, load a graphics backend, or produce screenshots.

This is useful for agent-driven interaction, reproducible UI regression tests,
and inspecting rendered text and geometry without OCR.

## Build and try the demo

Use Swift 6.4 or later on Linux or macOS. Build the executable once, then launch the binary directly
so build-tool output cannot become part of the protocol stream:

```sh
swift build --product ChromaHeadlessDemo
printf '%s\n' \
  '{"version":1,"id":"start","op":"frame"}' \
  '{"version":1,"id":"bye","op":"quit"}' \
  | .build/debug/ChromaHeadlessDemo --headless --viewport 800x600
```

`ChromaHeadlessDemo` is a headless-only executable; `--headless` is optional.
`--viewport WIDTHxHEIGHT` overrides the application's initial size. Without that
option the application's `windowSize` is used, which defaults to 800 by 600.
Invalid command-line options or dimensions exit nonzero and explain the problem
on stderr. The dedicated `ChromaHeadless` product depends on `Chroma` and
`ChromaTesting`, not the native rendering backends.

The demo contains two single-line text editors with placeholders `First` and
`Second`, followed by a `Count: 0` button. It uses desktop navigation bindings
with explicit plain Backspace and Delete editing bindings.
The Swift driver focuses the first editor, enters text, and prints the responses:

```sh
swift Tools/headless_client.swift .build/debug/ChromaHeadlessDemo --text "Hello Chroma"
swift Tools/test_headless_stdio.swift .build/debug/ChromaHeadlessDemo
```

The driver and integration tests are standalone Swift scripts using Foundation,
with no package dependencies.
Tests launch real subprocesses with stdin/stdout/stderr pipes, rather
than invoking the request decoder in-process. They cover burst input ordering,
repeated keys, pointer editing and button clicks, resizes, malformed and oversized
input recovery, byte limits, EOF, quit, and strict JSON-only stdout.

## Use an existing application

Applications using `NativeApp` can select the same transport at runtime:

```sh
YourApplication --headless --viewport 1024x768
```

This branches before a native host is created. The executable still has its
normal link-time dependencies; use `ChromaHeadless` for a separate executable
that does not depend on a native backend at all.

For a headless-only application, depend on the `ChromaHeadless` library product
and conform to `HeadlessApp` instead of `NativeApp`:

```swift
import Chroma
import ChromaHeadless

@main
struct AgentApp: HeadlessApp {
  var keyBindings: KeyBindings { .desktopNavigation }

  var body: some Block {
    Text("Ready for an agent")
  }
}
```

An application with its own entry point can call
`await HeadlessSession.runProcess(MyApp())`, or use the throwing
`HeadlessSession.run(MyApp(), arguments: ...)` entry point. Embedded tests may
instantiate `HeadlessSession` on the main actor and call `respond(to:)` without
using pipes. `HeadlessHost` remains available for direct in-process Swift tests.
The stdio launcher owns process-wide stdout redirection and SIGPIPE handling;
run only one stdio session per process. `NativeApp.main()` is now asynchronous.
Custom code that invokes that entry point directly must await it.

## Version 1 wire protocol

Requests are UTF-8 JSON objects, one per line. Every request must include
`"version": 1` and an `op` string. An optional string `id` is echoed in the
response; it is a correlation value, not a deduplication key. JSON whitespace is
allowed, including CRLF line endings. Unknown object fields are ignored.

There is no startup banner or unsolicited initial frame. Every accepted frame,
key, pointer, scroll, or resize request produces one `frame` response. Invalid
requests produce one `error` response without ending the session. `quit` produces
one `closed` response and exits. Requests are processed and answered in order,
including when the client writes many lines without waiting for responses.

### Frame

```json
{"version":1,"id":"snapshot","op":"frame"}
```

Take an explicit snapshot of the current application state. Repeated snapshots
of unchanged state are deterministic. A snapshot is a request boundary, not a
promise that all application-created asynchronous work has finished. Applications
can continue asynchronous work while stdin is idle; request another frame when
you want to inspect the result.

### Keyboard and text

```json
{"version":1,"id":"focus","op":"key","key":"tab"}
{"version":1,"id":"activate","op":"key","key":"enter"}
{"version":1,"id":"insert","op":"key","text":"Hello"}
{"version":1,"id":"select-back","op":"key","key":"left","modifiers":["shift"]}
```

Provide `key`, `text`, or both. `key` is one of `up`, `down`, `left`, `right`,
`tab`, `enter`, `escape`, `space`, `home`, `end`, `pageUp`, `pageDown`, `delete`,
`backspace`, or a single Swift `Character` (an extended grapheme cluster).
Optional `modifiers` is an array containing `shift`, `control`, `option`,
`command`, or `super`.

`text` supplies text input rather than a physical key's platform-dependent
character mapping. To type a character, provide `text`, even if you also provide
`key`. For example, `{"op":"key","version":1,"key":"a","text":"a"}`
models typing `a`; a `key` alone follows the application's key bindings.

Keys resolve against the application's bindings and the current interaction
mode. The transport does not override those bindings or force insertion into an
unfocused editor. With the demo's desktop bindings, Tab selects a control and
Enter activates editing; pointer clicking an editor also activates editing.
The default `App` bindings are modal navigation, so other applications may need
different focus/activation keys. Escape exits editing.

### Pointer

```json
{"version":1,"op":"pointer","phase":"move","x":30,"y":30}
{"version":1,"op":"pointer","phase":"down","x":30,"y":30}
{"version":1,"op":"pointer","phase":"up","x":30,"y":30}
```

Coordinates are in the viewport's logical coordinate space, with the origin at
the top left. Only the primary button is modeled. A click is a `down` followed by
an `up`; a drag adds `move` requests between them. Pointer and press positions
persist between requests, including keyboard events and frame requests.
Duplicate `down` or unmatched `up` requests return `invalid_pointer_transition`.
Use rendered geometry to choose locations rather than assuming fixed pixels.

### Scroll

```json
{"version":1,"op":"scroll","x":0,"y":-24}
```

Here `x` and `y` are horizontal and vertical scroll deltas, not pointer
coordinates. The current pointer position supplies the scroll target. Move the
pointer over the relevant scroll view first. Scroll routing and direction follow
Chroma's normal input pipeline; a view without scrollable content may not change.

### Resize and quit

```json
{"version":1,"op":"resize","width":1024,"height":768}
{"version":1,"id":"done","op":"quit"}
```

Resize updates the logical viewport and renders the resulting layout. Quit
closes the host and terminates the transport; later buffered requests are not
processed. EOF also closes the host successfully, without a synthetic response.
A final nonempty line without a trailing newline is processed at EOF. A malformed
final line yields an error response before closing.

## Responses

A frame response has this shape (the command list below is illustrative):

```json
{
  "version":1,
  "id":"snapshot",
  "status":"frame",
  "viewport":{"width":800,"height":600},
  "commands":[
    {"text":{"position":{"x":24,"y":24},"text":"First","color":{"r":0,"g":0,"b":0,"a":1},"scale":1}}
  ],
  "focus":{"editing":false}
}
```

`commands` is the ordered `DrawCommand` array encoded by Swift `Codable`, not an
accessibility tree or a raster image. Each enum case is a single-key object.
For example, text is under `command["text"]["text"]`, and its position is under
`command["text"]["position"]`. Other cases include fills, strokes, images, and
clip-stack changes; preserve their ordering when interpreting or replaying them.
The exact payloads are defined in
[`DrawCommand.swift`](../Sources/Chroma/Rendering/DrawCommand.swift).

`focus` describes the current interaction state: `editing` is always present;
`path`, `caretOffset`, `selectionStart`, and `selectionEnd` are included when
applicable. Paths are structural indices for inspecting the current frame, not
durable widget identifiers or selectors for future application versions. Text
selection offsets follow Chroma's character-based editing model.

Closed and error responses do not contain a frame:

```json
{"version":1,"id":"done","status":"closed"}
{"version":1,"id":"bad-size","status":"error","error":"invalid_viewport"}
```

Missing optional response fields are omitted rather than encoded as `null`.
Valid short string IDs are preserved on errors when recoverable; malformed JSON,
invalid UTF-8, overlong IDs, and oversized lines may have no response ID. Clients
should ignore response fields they do not use and validate `version` and `status`.

## Limits and recovery

- Maximum input line: 65,536 bytes, excluding the terminating LF. A CR in CRLF
  counts toward the limit. Oversized input is drained through the next LF, with
  one `line_too_long` response, so subsequent requests stay aligned.
- Viewport width and height: finite numbers in the inclusive range 1...16,384.
- Pointer coordinates and scroll deltas: finite numbers with absolute value at
  most 1,000,000.
- `text`: at most 16,384 UTF-8 bytes per request.
- `id`: at most 256 UTF-8 bytes.
- JSON `NaN`, `Infinity`, malformed JSON, wrong field types, unknown key names,
  unknown modifiers, and unsupported versions are rejected.

Error strings include `invalid_request`, `invalid_utf8`, `unsupported_version`,
`unknown_operation`, `invalid_viewport`, `invalid_pointer_transition`, and
`line_too_long`. An application that emits non-JSON-encodable draw geometry
receives `unencodable_frame`; the stream remains valid JSONL. Invalid requests do
not apply their requested state change.

Stdout is exclusively the JSONL response stream. Standard application stdout
logging is redirected to stderr while the stdio session owns the process, and
transport diagnostics also go to stderr. Drain both streams to avoid pipe
backpressure. Do not combine stderr with stdout in an agent's protocol parser.
Broken output pipes and other transport I/O failures exit with status 1 and a
stderr diagnostic when stderr is still available. This service's shutdown
contract is EOF or `quit`: cancelling its Swift task or calling an embedded
session's `close()` does not interrupt a pending blocking stdin read. A subprocess
owner should close stdin or terminate its child when cancelling.
The supplied Python client drains both independently, checks response deadlines,
and forcibly cleans up an unresponsive child on exit.

## Import the Python client

```python
import sys
sys.path.insert(0, "Tools")
from headless_client import HeadlessClient, frame_texts

with HeadlessClient(".build/debug/ChromaHeadlessDemo") as app:
    frame = app.request("frame", id="first")
    assert frame["status"] == "frame"
    print(frame_texts(frame))

    app.send_many([
        {"version": 1, "id": "next", "op": "key", "key": "tab"},
        {"version": 1, "id": "edit", "op": "key", "key": "enter"},
        {"version": 1, "id": "type", "op": "key", "text": "agent input"},
    ])
    for expected_id in ("next", "edit", "type"):
        response = app.receive()
        assert response["id"] == expected_id
        assert response["status"] == "frame"

    assert app.request("quit")["status"] == "closed"
    assert app.expect_eof() == 0
```

For long-running applications, frame the checks around observable UI outcomes.
The transport preserves input order and provides explicit snapshots; it does not
turn network requests, app-created tasks, or wall-clock-dependent application
state into synchronous or deterministic operations.

## Swift Subprocess E2E tests

```sh
Tools/test_headless_fixture.sh
```

This builds the demo and a standalone consumer in release mode, then runs Swift
Testing end-to-end tests with the official
[`swiftlang/swift-subprocess` 1.0.0](https://github.com/swiftlang/swift-subprocess/tree/1.0.0)
package. Its [1.0 API](https://github.com/swiftlang/swift-subprocess/blob/1.0.0/README.md)
requires Swift 6.2 or newer; this repository's Swift 6.4 toolchain is supported.
The dependency is confined to `Tests/HeadlessProcessFixture`; production Chroma
products gain no third-party runtime dependency. The fixture's `Package.resolved`
records the exact Subprocess and Swift System revisions.

The tests use `input: .inputWriter` and independent stdout/stderr `.sequence`
streams. Stdout framing splits only on LF, preserving Unicode line-separator
characters within JSON strings. They decode each response, wait for a correlated
response before
sending the next interactive request, and separately test a rapid ordered input
burst. They also cover malformed-request recovery, EOF, application logging,
main-actor async progress with stdin idle, output-pipe failure, and nonzero exits.
Concurrent stream draining and deadline/cancellation cleanup are exercised with
real child processes; cleanup checks verify that the child has been reaped.
This replaces the small Python fixture suite. The broader dependency-free Python
protocol suite and example client remain available.

Set `SWIFT` to a particular Swift executable, or `CONFIGURATION=debug` to test a
debug build. The wrapper builds and locates both executables before invoking
`swift test`. No Foundation `Process` substitute or prerecorded output is used.
The protocol remains usable with any streaming subprocess library: write each
UTF-8 request plus a newline, parse stdout line by line, drain stderr separately,
and close stdin or send `quit` when finished.

## Verification of this proposal

On Linux with Swift 6.4, the full package release build and all 490 Swift tests
(470 core, 13 Wayland backend, 7 headless session) pass. The release demo passes
19 real-pipe protocol tests; the standalone release consumer passes 11 Swift
Subprocess E2E tests. An optimized native-app fixture also runs its `--headless`
branch
with display-related environment variables removed. macOS/Metal execution has
not been verified; no native visual rendering or performance claim is made.
