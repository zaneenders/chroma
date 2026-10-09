#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFTC=${SWIFTC:-swiftc}
OUT=${OUT:-.build/compile-fail}
mkdir -p "$OUT/module-cache"
"$SWIFTC" -enable-experimental-feature Lifetimes -module-cache-path "$OUT/module-cache" \
  -emit-module -module-name FrameArena Sources/FrameArena/*.swift -emit-module-path "$OUT/FrameArena.swiftmodule"
# Positive control makes missing imports, toolchains, or bad flags fail the suite.
cat > "$OUT/positive.swift" <<'SWIFT'
import FrameArena
func accepted() {
    var arena = FrameArena<Int>()
    let h = arena.append(42)
    print(arena.view[arena.index(of: h)!])
    arena.reset()
    arena.append(99)
    print(arena.view[0])
}
SWIFT
"$SWIFTC" -enable-experimental-feature Lifetimes -module-cache-path "$OUT/module-cache" \
  -I "$OUT" -c "$OUT/positive.swift" -o "$OUT/positive.o"
for file in Tests/CompileFail/*.swift; do
  name=$(basename "$file" .swift)
  if "$SWIFTC" -enable-experimental-feature Lifetimes -module-cache-path "$OUT/module-cache" \
    -I "$OUT" -c "$file" -o "$OUT/$name.o" >"$OUT/$name.log" 2>&1; then
    echo "FAIL: $name unexpectedly compiled"; exit 1
  fi
  case "$name" in
    copy_owner|copy_slab) expected="cannot be applied to noncopyable" ;;
    slab_string|slab_closure) expected="conform to.*'BitwiseCopyable'" ;;
    store_view) expected="stored property.*non-escapable|Escapable" ;;
    view_outlives_owner|slab_view_outlives_owner) expected="lifetime-dependent value escapes|lifetime dependence" ;;
    *) expected="overlapping accesses|lifetime-dependent value escapes" ;;
  esac
  if ! grep -Eq "$expected" "$OUT/$name.log"; then
    echo "FAIL: $name failed for unexpected reason:"; cat "$OUT/$name.log"; exit 1
  fi
  echo "PASS (rejected): $name"
done
