#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFTC=${SWIFTC:-swiftc}
OUT=${OUT:-.build/trap-tests}
mkdir -p "$OUT/module-cache"
ulimit -c 0
cat > "$OUT/main.swift" <<'SWIFT'
switch CommandLine.arguments[1] {
case "negative-slab": _ = TrivialSlab<Int>(capacity: -1)
case "byte-overflow": _ = TrivialSlab<UInt64>(capacity: Int.max)
case "negative-arena": _ = FrameArena<Int>(reserving: -1)
case "negative-reserve":
    var a = FrameArena<Int>()
    a.reserveCapacity(-1)
case "generation-overflow": _ = nextGeneration(UInt64.max)
case "span-bounds":
    let a = FrameArena<Int>()
    print(a.view[0])
case "slab-span-bounds":
    let a = TrivialSlab<Int>(capacity: 4)
    print(a.view[0])
default: fatalError("Unknown test")
}
SWIFT
"$SWIFTC" -Onone -enable-experimental-feature Lifetimes -module-cache-path "$OUT/module-cache" \
  Sources/FrameArena/*.swift "$OUT/main.swift" -o "$OUT/trap-tests"
for test in negative-slab byte-overflow negative-arena negative-reserve generation-overflow span-bounds slab-span-bounds; do
  if "$OUT/trap-tests" "$test" >"$OUT/$test.log" 2>&1; then
    echo "FAIL: $test did not trap"; exit 1
  fi
  case "$test" in
    byte-overflow) expected="Slab byte count overflow" ;;
    generation-overflow) expected="Arena generation exhausted" ;;
    *bounds) expected="[Ii]ndex out of bounds|[Ii]ndex out of range" ;;
    *) expected="Precondition failed" ;;
  esac
  if ! grep -Eq "$expected" "$OUT/$test.log"; then
    echo "FAIL: unexpected $test error:"; cat "$OUT/$test.log"; exit 1
  fi
  echo "PASS (trapped): $test"
done
