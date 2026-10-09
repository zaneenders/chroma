# Local validation on your own compute

Validation is started explicitly on your own Linux or macOS machine. This change
contains no GitHub Actions workflow, automatic pull-request/push trigger, hosted
runner, self-hosted runner registration, or schedule. Repository Actions settings
are not changed. Opening or updating a PR does not start these scripts.

From a clean checkout, start with the inexpensive prerequisite check:

```sh
bash Scripts/validate.sh preflight
```

When you are ready to use your machine's compute, run the full check set:

```sh
CHROMA_BUILD_JOBS=2 bash Scripts/validate.sh
```

This runs strict Swift formatting, all three packages' tests, all three release
builds, and a lockfile-drift check, sequentially and stopping on the first failure.
`CHROMA_BUILD_JOBS` defaults to 2; choose a positive integer for your machine.
Benchmark report collection is separate and is not started by this command.
Additional arguments after the stage are forwarded to Swift build/test commands
(for example, `-Xcc -I/path/to/custom/include` for a non-system SDK).
For a smaller iteration, run only the relevant stage:

```sh
bash Scripts/validate.sh format
bash Scripts/validate.sh root-tests
bash Scripts/validate.sh benchmark-tests
bash Scripts/validate.sh headless-tests
bash Scripts/validate.sh root-release
bash Scripts/validate.sh benchmark-release
bash Scripts/validate.sh headless-release
bash Scripts/validate.sh lockfiles
```

No test filters or stderr suppression are used. Formatting includes both backends
even when only one backend can execute on the host. A failed test or unavailable
GPU fails its check; it is not silently reported as covered.

## Prerequisites and platform coverage

- **Swift 6.4** (see `.swift-version` and all three package manifests).
- **Linux:** Wayland **1.26+** development headers/libraries, EGL, OpenGL ES 3,
  libxkbcommon and its keyboard data. `WaylandHost` uses the `warp` callback added
  to `wl_pointer_listener` in Wayland 1.26. Older distro development packages are
  insufficient even if the machine already runs a Wayland desktop.
- **macOS:** macOS **27+**, Xcode **27.0** with its Swift 6.4 toolchain and a working
  Metal device. The package deployment target requires macOS 27 to execute tests.
  Select the intended Xcode toolchain before running the checks.

### Optional local Wayland build

If your distro lacks Wayland 1.26, `Scripts/build-wayland.sh` downloads the official
1.26.0 release, verifies its SHA256, and builds it into an explicit caller-owned
prefix. It requires a C toolchain, curl, tar/xz, Meson, Ninja, pkg-config, libffi
and Expat development files. Install distro EGL/GLES/Mesa and keyboard dependencies
separately. The helper does not install those packages or use elevated privileges.

```sh
bash Scripts/build-wayland.sh "$HOME/.local/chroma-wayland-1.26"
export PKG_CONFIG_PATH="$HOME/.local/chroma-wayland-1.26/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$HOME/.local/chroma-wayland-1.26/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
bash Scripts/validate.sh preflight
```

The prefix is isolated from the system Wayland installation. If intentionally
checking Mesa software rendering instead of your hardware driver, invoke the test
stage with `LIBGL_ALWAYS_SOFTWARE=1 EGL_PLATFORM=surfaceless`. A surfaceless EGL
pbuffer exercises renderer behavior; it does not exercise a Wayland compositor.

| Check | Local Linux | Local macOS | Separate native smoke |
| --- | --- | --- | --- |
| Core, Markdown, focus/navigation/observation tests | Yes | Yes | — |
| Real child-process JSONL/headless tests | Yes | Yes | — |
| Benchmark fixtures and comparison tests | Yes | Yes | — |
| Renderer pixels, batching, uploads, frame resources | EGL/GLES device required | Metal device required | Hardware/driver-specific coverage |
| Clipboard, native input ordering, focus, resize/scale | Not an interactive app session | Not an interactive app session | Required on each platform |
| IME composition | Not established | Not established | Track implementation/acceptance in #107 |
| Hardware presentation/scroll performance | Separate measurement | Separate measurement | Track in #111 |

## Clean dependency resolution

All three `Package.resolved` files are intentionally tracked. Test and release
commands use `--force-resolved-versions`, so an outdated lockfile fails rather than
silently changing dependency versions. When changing dependencies, deliberately run:

```sh
swift package resolve
swift package --package-path Benchmarks resolve
swift package --package-path HeadlessModeTests resolve
```

Review and commit the three lockfiles with the manifest change, then validate a
clean checkout. The nested packages also resolve the root package's Markdown/cmark
dependencies. Do not discard those pins as unrelated resolver noise.

## Local logs and optional benchmarks

Output remains on your machine. To retain a validation log while preserving a
failing exit status, run:

```sh
mkdir -p validation-results
git rev-parse HEAD > validation-results/revision.txt
swift --version > validation-results/toolchain.txt
bash -o pipefail -c 'bash Scripts/validate.sh 2>&1 | tee validation-results/validation.log'
```

Run benchmark collection only when you want to spend compute on it, with other
builds and profiling processes idle:

```sh
bash Benchmarks/Scripts/run.sh validation-results/benchmarks
# Optional backend replay on the corresponding local platform:
# OPENGL=1 bash Benchmarks/Scripts/run.sh validation-results/opengl-benchmarks
# METAL=1 bash Benchmarks/Scripts/run.sh validation-results/metal-benchmarks
```

The benchmark script retains revision/worktree state, dependency/toolchain/hardware
metadata and workload reports in the chosen directory; it refuses to overwrite a
nonempty output directory. Nothing is uploaded automatically. Compare repeated
trials on matching hardware, toolchains, dependencies and workloads using
[Benchmarks/README.md](Benchmarks/README.md). Timings are informational; deterministic
work-count/resource assertions remain ordinary tests. Software EGL results establish
only tested pixels/behavior, not a hardware GPU performance baseline.

## Diagnosing failures

Earlier restricted Linux environments emitted `swift-backtrace` path/environment
protection warnings on child stderr. Those are environment/toolchain diagnostics,
not evidence of a rendering defect. Keep the headless suite's stderr assertions:
inspect full stderr and the installed toolchain's permissions/path. Do not broadly
ignore stderr or globally disable backtracing to get green.

Session watchdogs still default to 10 seconds. The 256-response stdout-draining
functional test has a 30-second bound because full-frame debug JSON work can exceed
10 seconds on shared hosts. Its burst size, response ordering and EOF assertions
are unchanged. A separate one-second override test verifies timeout cancellation
and child reaping. This test-only guard is also included in #124; it does not
incorporate that PR's production reader changes.

## Native smoke record

For each macOS/Wayland session, record commit, OS, Swift/Xcode, GPU/driver,
compositor (Wayland), display scale, and each check's **passed**, **failed**,
**skipped** or **unavailable** status. Use a runnable demo from `chroma-examples`:

1. Select multiline text; copy, paste and replace it. Check ordering of native
   text/key input, including repeated keys. Do not claim unsupported IME coverage.
2. Move focus away and back, including switching apps and clicking another editor.
3. Resize repeatedly and move between displays/scales. Check clips, text and pointer
   coordinates after each change.
4. Close and reopen; verify clean shutdown and repeat several times to look for
   accumulating windows/resources or stale callbacks.

Keep this record separate from headless tests and offscreen renderer tests. The
validation scripts do not perform these interactive checks.

## Historical evidence

Before the switch to local-only validation, hosted
[run 37908290904](https://github.com/zaneenders/chroma/actions/runs/37908290904)
passed for revision `24d96c19ad2230d35bdedcac3509bac01be1de1f` on Linux and macOS.
That is historical evidence for the earlier revision, not a run on your home
machine or a fresh runtime validation of this documentation/workflow-removal
revision. The hosted workflow has been removed; no new run is requested.
