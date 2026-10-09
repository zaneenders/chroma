# Validation

Run `bash Scripts/validate.sh` from a clean checkout. It runs strict Swift formatting,
all three packages' tests, all three release builds, and a lockfile-drift check.
`CHROMA_BUILD_JOBS` defaults to 2; set a positive integer for your machine.
Additional arguments after the stage are forwarded to Swift build/test commands
(for example, `-Xcc -I/path/to/custom/include` for a non-system SDK).
Individual stages are available for diagnosis, for example:

```sh
bash Scripts/validate.sh preflight
bash Scripts/validate.sh root-tests
bash Scripts/validate.sh benchmark-tests
bash Scripts/validate.sh headless-tests
```

The `.github/workflows/validation.yml` jobs run these same commands on pull requests,
pushes to `main`, and manual dispatch. No test filters or stderr suppression are used.
Formatting includes both backends even when only one backend can execute on the host.
A failed test or unavailable GPU fails its check; it is not silently reported as covered.

## Prerequisites and runner matrix

- **Swift 6.4** (see `.swift-version` and all three package manifests).
- **Linux:** Wayland **1.26+** development headers/libraries, EGL, OpenGL ES 3,
  libxkbcommon and its keyboard data. `WaylandHost` uses the `warp` callback added
  to `wl_pointer_listener` in Wayland 1.26. Older distro development packages are
  insufficient even if the machine already runs a Wayland desktop.
- **macOS:** macOS **27+**, Xcode **27.0** with its Swift 6.4 toolchain and a working
  Metal device. The package deployment target requires macOS 27 to execute tests.

CI uses the official [Swift 6.4.0 Ubuntu 24.04 container](https://www.swift.org/install/linux/ubuntu/24_04/)
on `ubuntu-24.04`. It checks out into a new `source/` child owned by the
container user, so Git ownership checks remain enabled without a trust override.
`Scripts/build-ci-wayland.sh` downloads the official Wayland 1.26.0
release, checks its SHA256, and builds it into `/opt/chroma-wayland`. It does not
replace the runner's system Wayland installation. The workflow installs distro
EGL/GLES/Mesa and keyboard dependencies separately. Mesa software rendering and a
surfaceless EGL pbuffer exercise the OpenGL pixel, upload, and batching tests.

The macOS job selects the [`xcode-27` public-preview image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
and `/Applications/Xcode_27.0.app`. That runner label is a maintained image, not
an immutable OS snapshot. Both jobs record the actual OS and toolchain version.
If the preview image is withdrawn, its Xcode path changes, or no Metal device is
available, fix the runner configuration rather than skipping native tests.
The first hosted run must establish the actual Metal coverage; merely adding this
workflow or passing Linux tests is not evidence of a macOS test pass.

| Check | Linux CI | macOS CI | Separate native smoke |
| --- | --- | --- | --- |
| Core, Markdown, focus/navigation/observation tests | Yes | Yes | — |
| Real child-process JSONL/headless tests | Yes | Yes | — |
| Benchmark fixtures and comparison tests | Yes | Yes | — |
| Renderer pixels, batching, uploads, frame resources | Mesa software EGL | Metal device required | Hardware/driver-specific coverage |
| Clipboard, native input ordering, focus, resize/scale | No compositor | Not an interactive app session | Required on each platform |
| IME composition | Not established | Not established | Track implementation/acceptance in #107 |
| Hardware presentation/scroll performance | No | No stable hardware baseline | Track in #111 |

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

## Failures and evidence

CI retains `validation-results` for 14 days, including command logs, actual
revision/worktree state, toolchain, OS/hardware details and the benchmark script's
workload/dependency metadata. For a pull request, the tested revision may be the
GitHub merge ref; `environment.txt` and the benchmark `revision.txt` identify it.
Canceled jobs may not upload artifacts. A failed build/test remains failed even
when later independent checks run to collect additional diagnostics.

Earlier restricted Linux environments emitted `swift-backtrace` path/environment
protection warnings on child stderr. Those are environment/toolchain diagnostics,
not evidence of a rendering defect. Keep the headless suite's stderr assertions:
inspect the full stderr and the installed toolchain's permissions/path on a failing
runner. Do not broadly ignore stderr or globally disable backtracing to get green.

`Benchmarks/Scripts/run.sh` captures informational cull/stress and backend replay
reports after successful checks. These timings do **not** gate shared-runner CI.
The existing deterministic work-count/resource assertions remain ordinary tests.
For meaningful performance comparisons, use the repeated-trial baseline and
comparison procedure in [Benchmarks/README.md](Benchmarks/README.md) on matching
hardware, toolchain, dependencies and workloads. Software EGL results establish
only tested pixels/behavior; they are neither a GPU performance baseline nor a
Wayland compositor test.

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
workflow does not perform these interactive checks, provision a custom runner,
modify repository settings, merge code, or deploy an application.
