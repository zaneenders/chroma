#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
out=${1:-Benchmarks/results/run}
if [ -e "$out" ] && { [ ! -d "$out" ] || [ -n "$(ls -A "$out")" ]; }; then
  echo "Refusing to overwrite results: $out" >&2
  exit 1
fi
swift build --package-path Benchmarks -c release --product RenderBenchmark
bin=$(swift build --package-path Benchmarks -c release --show-bin-path)/RenderBenchmark
toolchain=$(swift --version)
revision=$(git rev-parse HEAD)
worktree=$(git status --short)
dependencies=$(swift package --package-path Benchmarks show-dependencies --format json)
if [ "$(uname -s)" = Darwin ]; then
  hardware=$(uname -m; sysctl -n hw.model; sysctl -n machdep.cpu.brand_string)
else
  hardware=$(uname -m; lscpu | grep -E 'Architecture:|Model name:|CPU\(s\):')
fi
mkdir -p "$out"
printf '%s\n' "$toolchain" > "$out/toolchain.txt"
printf '%s\n' "$revision" > "$out/revision.txt"
printf '%s\n' "$worktree" > "$out/worktree.txt"
printf '%s\n' "$dependencies" > "$out/dependencies.json"
printf '%s\n' "$hardware" > "$out/hardware.txt"
for scene in ${SCENES:-shapes text clipped images transcript streaming scrolling selection composer}; do
  "$bin" --scene "$scene" --stage cull > "$out/$scene-cull.json"
  if [ "$(uname -s)" = Darwin ] && [ "${METAL:-0}" = 1 ]; then
    "$bin" --scene "$scene" --stage metal > "$out/$scene-metal.json"
  fi
done
