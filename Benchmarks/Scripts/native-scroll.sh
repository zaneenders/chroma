#!/bin/sh
set -eu
umask 077
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
usage() { echo 'Usage: native-scroll.sh NEW_OUTPUT_DIR APP_PACKAGE PRODUCT CHROMA_SOURCE WORKLOAD_LABEL [-- app arguments]' >&2; exit 1; }
[ "$#" -ge 5 ] || usage
out=$1
app=$(CDPATH= cd -- "$2" && pwd)
product=$3
source=$(CDPATH= cd -- "$4" && pwd)
workload=$5
shift 5
if [ "$#" -gt 0 ]; then [ "$1" = -- ] || usage; shift; fi
[ "$(uname -s)" = Linux ] || { echo 'Native trace requires Linux/Wayland.' >&2; exit 1; }
[ -n "${XDG_RUNTIME_DIR:-}" ] && [ -n "${WAYLAND_DISPLAY:-}" ] || {
  echo 'Run from a desktop terminal with XDG_RUNTIME_DIR and WAYLAND_DISPLAY.' >&2; exit 1;
}
case "$WAYLAND_DISPLAY" in /*) socket=$WAYLAND_DISPLAY ;; *) socket=$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ;; esac
[ -S "$socket" ] || { echo 'Wayland socket unavailable.' >&2; exit 1; }
[ ! -e "$out" ] || { echo 'Refusing to overwrite output.' >&2; exit 1; }
mkdir -p "$out"
out=$(CDPATH= cd -- "$out" && pwd)
refresh=${NATIVE_REFRESH_HZ:-60}
seconds=${CHROMA_NATIVE_TRACE_SECONDS:-30}
cat > "$out/settings.txt" <<EOF
workload=$workload
product=$product
appPackage=$app
chromaSource=$source
configuration=release
swiftFlags=-g
refreshHz=$refresh
captureSeconds=$seconds
traceCapacity=${CHROMA_NATIVE_TRACE_CAPACITY:-60000}
workCounters=${CHROMA_NATIVE_TRACE_WORK:-1}
stressWorkload=${CHROMA_STRESS_WORKLOAD:-identified}
stressRows=${CHROMA_STRESS_ROWS:-100000}
stressPanes=${CHROMA_STRESS_PANES:-3}
stressDepth=${CHROMA_STRESS_DEPTH:-8}
markdownSections=${CHROMA_STRESS_MARKDOWN_SECTIONS:-200}
stressMinHz=${CHROMA_STRESS_MIN_HZ:-30}
stressMaxHz=${CHROMA_STRESS_MAX_HZ:-60}
EOF
swift --version > "$out/toolchain.txt"
uname -a > "$out/kernel.txt"
lscpu > "$out/cpu.txt"
git -C "$source" rev-parse HEAD > "$out/chroma-revision.txt"
git -C "$source" status --short > "$out/chroma-worktree.txt"
git -C "$app" rev-parse HEAD > "$out/app-revision.txt"
git -C "$app" status --short > "$out/app-worktree.txt"
if command -v hyprctl >/dev/null 2>&1; then
  hyprctl version > "$out/compositor.txt" 2>&1 || true
  hyprctl -j monitors > "$out/monitors.json" 2>&1 || true
fi
if command -v pacman >/dev/null 2>&1; then
  pacman -Q hyprland mesa wayland wayland-protocols > "$out/platform-packages.txt" 2>&1 || true
fi
swift package --package-path "$app" show-dependencies --format json > "$out/dependency-graph.json" 2> "$out/dependencies.log"
python3 - "$out/dependency-graph.json" "$source" <<'PY'
import json, os, sys
with open(sys.argv[1], encoding="utf-8") as file:
    graph = json.load(file)
def paths(node):
    found = [node.get("path", "")] if node.get("identity") == "chroma" else []
    return found + [path for child in node.get("dependencies", []) for path in paths(child)]
if os.path.realpath(sys.argv[2]) not in [os.path.realpath(path) for path in paths(graph)]:
    sys.exit("Chroma dependency does not use the requested source checkout; configure a local override first.")
PY
swift build --package-path "$app" -c release -Xswiftc -g --product "$product" > "$out/build.log" 2>&1
[ ! -f "$app/Package.resolved" ] || cp "$app/Package.resolved" "$out/Package.resolved"
bin_dir=$(swift build --package-path "$app" -c release --show-bin-path)
bin=$bin_dir/$product
printf '%s\n' "$bin" > "$out/executable.txt"
sha256sum "$bin" > "$out/executable.sha256"
file "$bin" > "$out/executable-format.txt"
if command -v readelf >/dev/null 2>&1; then
  readelf -n "$bin" > "$out/executable-notes.txt"
  readelf -S "$bin" > "$out/executable-sections.txt"
fi
printf 'Capture %ss: perform the labelled gesture, release into momentum, then leave idle. Close the app after capture.\n' "$seconds"
status=0
CHROMA_NATIVE_TRACE="$out/trace.json" CHROMA_NATIVE_TRACE_SECONDS="$seconds" "$bin" "$@" || status=$?
printf '%s\n' "$status" > "$out/exit-status.txt"
[ -f "$out/trace.json" ] || { echo 'No trace written; see build.log/exit-status.txt.' >&2; exit 1; }
python3 "$root/Benchmarks/Scripts/native_trace.py" "$out/trace.json" --refresh-hz "$refresh" > "$out/summary.json"
printf 'Saved %s/summary.json\n' "$out"
exit "$status"
