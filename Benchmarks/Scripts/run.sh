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
bin=$(swift build --package-path Benchmarks -c release --show-bin-path)/RenderBenchmark
swift --version > "$out/toolchain.txt"
git rev-parse HEAD > "$out/revision.txt"
git status --short > "$out/worktree.txt"
cp Benchmarks/Package.resolved "$out/dependencies.json"
if [ "$(uname -s)" = Darwin ]; then
  { uname -m; sysctl -n hw.model; sysctl -n machdep.cpu.brand_string; } > "$out/hardware.txt"
else
  { uname -m; lscpu | grep -E 'Architecture:|Model name:|CPU\(s\):'; } > "$out/hardware.txt"
fi
unset PROFILE_RECORDER_SERVER_URL_PATTERN PROFILE_RECORDER_SERVER_URL
for scene in ${SCENES:-shapes text clipped images transcript streaming scrolling selection composer}; do
  "$bin" --scene "$scene" --stage wire > "$out/$scene-wire.json"
  if [ "$(uname -s)" = Darwin ] && [ "${METAL:-0}" = 1 ]; then
    "$bin" --scene "$scene" --stage metal > "$out/$scene-metal.json"
    "$bin" --scene "$scene" --stage pipeline > "$out/$scene-pipeline.json"
  fi
done
