#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
out=${1:?usage: baseline.sh OUTPUT_DIRECTORY [TRIALS]}
trials=${2:-5}
case "$trials" in ''|*[!0-9]*) echo 'TRIALS must be an integer' >&2; exit 1;; esac
if [ "$trials" -lt 3 ] || [ "$trials" -gt 30 ]; then
  echo 'Use 3–30 trials' >&2
  exit 1
fi
if [ -e "$out" ]; then
  echo "Refusing to overwrite baseline: $out" >&2
  exit 1
fi
mkdir -p "$out"
i=1
while [ "$i" -le "$trials" ]; do
  Benchmarks/Scripts/run.sh "$out/trial-$i"
  i=$((i + 1))
done
