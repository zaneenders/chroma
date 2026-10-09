#!/bin/sh
# Run from any directory. Optional argument selects another checkout's reader.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
source_root=${1:-$root}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
swiftc -O -swift-version 6 -warnings-as-errors "$source_root/Sources/ChromaHeadless/BoundedLineReader.swift" \
  "$root/Benchmarks/Diagnostics/JSONLInput/main.swift" -o "$work/jsonl-input"
"$work/jsonl-input"
