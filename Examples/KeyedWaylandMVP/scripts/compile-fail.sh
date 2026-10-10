#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFTC=${SWIFTC:-swiftc}
OUT=${OUT:-.build/lifetime-checks}
mkdir -p "$OUT/module-cache"
FLAGS=(-enable-experimental-feature Lifetimes -module-cache-path "$OUT/module-cache")
"$SWIFTC" "${FLAGS[@]}" -emit-module -module-name FrameArena Vendor/FrameArena/Sources/FrameArena/*.swift -emit-module-path "$OUT/FrameArena.swiftmodule"
"$SWIFTC" "${FLAGS[@]}" -I "$OUT" -emit-module -module-name KeyedUI Sources/KeyedUI/*.swift -emit-module-path "$OUT/KeyedUI.swiftmodule"
cat > "$OUT/positive.swift" <<'SWIFT'
import KeyedUI
func valid() {
    var ui = UIStore()
    ui.frame(build: { frame in
        frame.beginColumn(in: Rect(0, 0, 100, 40))
        frame.button(key: 1, "A")
        frame.end()
    }, present: { draws in print(draws.count) })
}
SWIFT
"$SWIFTC" "${FLAGS[@]}" -I "$OUT" -c "$OUT/positive.swift" -o "$OUT/positive.o"
for file in Tests/CompileFail/*.swift; do
    name=$(basename "$file" .swift)
    if "$SWIFTC" "${FLAGS[@]}" -I "$OUT" -c "$file" -o "$OUT/$name.o" > "$OUT/$name.log" 2>&1; then
        echo "FAIL: $name unexpectedly compiled"; exit 1
    fi
    grep -Eq 'escaping closure captures .inout.|lifetime-dependent variable.*escapes' "$OUT/$name.log" || { cat "$OUT/$name.log"; exit 1; }
    echo "PASS (rejected): $name"
done
