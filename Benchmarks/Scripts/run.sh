#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
out=${1:-Benchmarks/results}
if [ -d "$out" ] && [ -n "$(ls -A "$out")" ]; then
  echo "Refusing to overwrite nonempty results directory: $out" >&2
  exit 1
fi
mkdir -p "$out"
swift build --package-path Benchmarks -c release --product RenderBenchmark
swift build --package-path Benchmarks -c release --product StressBenchmark
bin=$(swift build --package-path Benchmarks -c release --show-bin-path)/RenderBenchmark
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
  { uname -m; lscpu | grep -E 'Architecture:|Model name:|CPU\(s\):'; } > "$out/hardware.txt"
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
