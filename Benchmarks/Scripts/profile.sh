#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
out=${1:-Benchmarks/results/profile}
scene=${2:-text}
stage=${3:-metal}
mkdir -p "$out"
swift build --package-path Benchmarks -c release --product RenderBenchmark
bin=$(swift build --package-path Benchmarks -c release --show-bin-path)/RenderBenchmark
scratch=$(mktemp -d /tmp/chroma-profile.XXXXXX)
socket="$scratch/recorder.sock"
pid=
cleanup() {
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$scratch"
}
trap cleanup EXIT HUP INT TERM
PROFILE_RECORDER_SERVER_URL_PATTERN="unix://$socket" \
  "$bin" --scene "$scene" --stage "$stage" --seconds 20 \
  > "$out/profile-run.json" 2> "$out/recorder.log" &
pid=$!
attempt=0
while [ ! -S "$socket" ]; do
  if ! kill -0 "$pid" 2>/dev/null || [ "$attempt" -ge 100 ]; then
    echo "Recorder failed to start; see $out/recorder.log" >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done
sleep 2
curl --fail --silent --show-error --max-time 15 --unix-socket "$socket" \
  -d '{"numberOfSamples":500,"timeInterval":"10ms"}' \
  http://localhost/sample > "$out/samples.perf"
test -s "$out/samples.perf"
wait "$pid"
pid=
echo "Profile: $out/samples.perf (open in Speedscope)"
