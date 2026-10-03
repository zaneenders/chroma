# Headless mode tests

Run from this directory:

```sh
swift test
```

Or from the repository root:

```sh
swift test --package-path HeadlessModeTests
```

SwiftPM builds the demo and fixture as test dependencies. The tests locate those
executables alongside the test bundle and drive them as real child processes
using Swift Subprocess. No environment variables or separate build steps are required.

Release tests can be run with `swift test -c release`.

Headless executables emit an initial JSONL frame without a stdin request, then
emit only when the UI changes by default. Pass `--all-changes` to emit
continuously using the app’s maximum refresh rate, including unchanged frames. Streamed frames have
no request ID; responses to stdin requests echo the supplied ID. EOF or `quit`
closes the session. Async and timer tests wait for streamed stdout frames.

Headless CLI startup requires `--viewport WIDTHxHEIGHT`, for example:

```sh
swift run FallingBlocksDemo --headless --viewport 800x600
```
