#!/usr/bin/env bash
# Default: real Wayland/EGL client inside isolated Weston. --egl: shader-only smoke.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
MODE=${1:-wayland}
[[ "$MODE" == wayland || "$MODE" == --egl ]] || { echo "Usage: $0 [--egl]" >&2; exit 2; }
SWIFT=${SWIFT:-swift}
OUT=${SMOKE_OUT:-"$ROOT/.build-native/${MODE#--}-smoke"}
BUILD=${NATIVE_BUILD_PATH:-"$ROOT/.build-native"}
mkdir -p "$OUT" "$OUT/module-cache" "$OUT/package-cache" "$OUT/mesa-cache"
OUT=$(cd "$OUT" && pwd)
export CLANG_MODULE_CACHE_PATH="$OUT/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$OUT/module-cache"
export MVP_NATIVE=1 LIBGL_ALWAYS_SOFTWARE=1
export MESA_SHADER_CACHE_DIR="$OUT/mesa-cache"
BUILD_FLAGS=(-c release --scratch-path "$BUILD" --cache-path "$OUT/package-cache")
if [[ -n ${NATIVE_DEPS_ROOT:-} ]]; then
    DEPS=$(cd "$NATIVE_DEPS_ROOT" && pwd)
    ARCH=${NATIVE_MULTIARCH:-$(gcc -dumpmachine)}
    LIB="$DEPS/usr/lib/$ARCH"
    BUILD_FLAGS+=(-Xcc "-I$DEPS/usr/include" -Xlinker "-L$LIB")
    export LD_LIBRARY_PATH="$LIB:$LIB/weston${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    WESTON=${WESTON:-"$DEPS/usr/bin/weston"}
    # Weston officially supports module remapping for uninstalled builds.
    export WESTON_MODULE_MAP=${WESTON_MODULE_MAP:-}
    for module in "$LIB"/libweston-*/*.so "$LIB"/weston/*.so; do
        [[ -f "$module" ]] || continue
        WESTON_MODULE_MAP+="${WESTON_MODULE_MAP:+;}$(basename "$module")=$module"
    done
else
    WESTON=${WESTON:-weston}
fi
"$SWIFT" build "${BUILD_FLAGS[@]}" 2>&1 | tee "$OUT/build.log"
BIN=$("$SWIFT" build "${BUILD_FLAGS[@]}" --show-bin-path)/keyed-demo
if [[ "$MODE" == --egl ]]; then
    timeout 30 "$BIN" --egl-smoke --frames "${SMOKE_FRAMES:-12}" --screenshot "$OUT/egl.ppm" \
        2>&1 | tee "$OUT/client.log"
    python3 - "$OUT/egl.ppm" <<'PYVALIDATE'
import sys
with open(sys.argv[1], 'rb') as f:
    assert f.readline() == b'P6\n'
    width, height = map(int, f.readline().split())
    assert f.readline() == b'255\n'
    pixels = f.read()
assert len(pixels) == width * height * 3, 'truncated screenshot'
assert len(set(zip(pixels[0::3], pixels[1::3], pixels[2::3]))) > 10, 'blank screenshot'
print(f'EGL surfaceless smoke passed: {width}x{height}; no Wayland presentation')
PYVALIDATE
    printf 'Screenshot: %s/egl.ppm\n' "$OUT"
    exit 0
fi
# Use a new directory each run so stale sockets cannot masquerade as readiness.
export XDG_RUNTIME_DIR
XDG_RUNTIME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/keyed-wayland.XXXXXX")
chmod 700 "$XDG_RUNTIME_DIR"
export WAYLAND_DISPLAY=wayland-keyed-smoke
WESTON_PID=
cleanup() {
    if [[ -n "$WESTON_PID" ]]; then
        kill "$WESTON_PID" 2>/dev/null || true
        wait "$WESTON_PID" 2>/dev/null || true
    fi
    rm -rf "$XDG_RUNTIME_DIR"
}
trap cleanup EXIT
"$WESTON" --backend=headless --renderer=pixman --shell=kiosk \
    --socket="$WAYLAND_DISPLAY" --width=900 --height=660 --idle-time=0 \
    --no-config --log="$OUT/weston.log" >"$OUT/weston-stdout.log" 2>&1 &
WESTON_PID=$!
for _ in $(seq 1 100); do
    [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] && break
    if ! kill -0 "$WESTON_PID" 2>/dev/null; then
        cat "$OUT/weston.log" >&2
        echo "Weston exited before creating its Wayland socket. Unix sockets must be allowed." >&2
        exit 1
    fi
    sleep 0.05
done
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] || {
    echo "Weston did not create its socket within five seconds." >&2; exit 1;
}
timeout 30 "$BIN" --frames "${SMOKE_FRAMES:-12}" --screenshot "$OUT/native.ppm" \
    2>&1 | tee "$OUT/client.log"
python3 - "$OUT/native.ppm" <<'PY'
import sys
with open(sys.argv[1], 'rb') as f:
    assert f.readline() == b'P6\n'
    width, height = map(int, f.readline().split())
    assert f.readline() == b'255\n'
    pixels = f.read()
assert len(pixels) == width * height * 3, 'truncated screenshot'
assert len(set(zip(pixels[0::3], pixels[1::3], pixels[2::3]))) > 10, 'blank screenshot'
print(f'Wayland smoke passed: {width}x{height}, {len(pixels)} RGB bytes')
PY
printf 'Screenshot: %s/native.ppm\n' "$OUT"
