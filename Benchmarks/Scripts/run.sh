#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
out=${1:-Benchmarks/results}
if [ "$#" -gt 0 ]; then shift; fi
jobs=${CHROMA_BUILD_JOBS:-2}
case "$jobs" in ''|*[!0-9]*|0) echo 'CHROMA_BUILD_JOBS must be a positive integer' >&2; exit 2;; esac
if [ -d "$out" ] && [ -n "$(ls -A "$out")" ]; then
  echo "Refusing to overwrite nonempty results directory: $out" >&2
  exit 1
fi
mkdir -p "$out"
swift build --package-path Benchmarks -c release --force-resolved-versions --jobs "$jobs" "$@" --product RenderBenchmark
swift build --package-path Benchmarks -c release --force-resolved-versions --jobs "$jobs" "$@" --product StressBenchmark
bin=$(swift build --package-path Benchmarks -c release --force-resolved-versions --jobs "$jobs" "$@" --show-bin-path)/RenderBenchmark
swift --version > "$out/toolchain.txt"
git rev-parse HEAD > "$out/revision.txt"
git status --short > "$out/worktree.txt"
if [ -f Benchmarks/Package.resolved ]; then
  cp Benchmarks/Package.resolved "$out/dependencies.json"
else
  swift package --package-path Benchmarks show-dependencies --format json > "$out/dependencies.json"
fi
if [ "$(uname -s)" = Darwin ]; then
  { uname -m; sysctl -n hw.model; sysctl -n machdep.cpu.brand_string; } > "$out/hardware.txt"
else
  {
    uname -m
    if cpu_info=$(LC_ALL=C lscpu 2>&1); then
      printf '%s\n' "$cpu_info" | grep -E 'Architecture:|Model name:|CPU\(s\):'
    else
      # Restricted containers may not expose the sysfs topology used by lscpu.
      printf 'lscpu unavailable: %s\n' "$cpu_info"
      printf 'Online CPUs: '
      getconf _NPROCESSORS_ONLN
      grep -m 1 -E 'model name|Hardware' /proc/cpuinfo || echo 'CPU model unavailable'
    fi
  } > "$out/hardware.txt"
fi
for scene in ${SCENES:-shapes text clipped images transcript streaming scrolling selection composer}; do
  "$bin" --scene "$scene" --stage cull > "$out/$scene-cull.json"
  if [ "$(uname -s)" = Darwin ] && [ "${METAL:-0}" = 1 ]; then
    "$bin" --scene "$scene" --stage metal > "$out/$scene-metal.json"
  fi
  if [ "$(uname -s)" = Linux ] && [ "${OPENGL:-0}" = 1 ]; then
    "$bin" --scene "$scene" --stage opengl > "$out/$scene-opengl.json"
  fi
done

"$(dirname "$bin")/StressBenchmark" > "$out/stress-headless.json"
