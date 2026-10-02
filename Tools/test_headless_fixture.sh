#!/usr/bin/env bash
# Build real executables, then drive their pipes with swiftlang/swift-subprocess.
# Usage: SWIFT=/path/to/swift Tools/test_headless_fixture.sh
# SWIFTC=/path/to/swiftc also selects the adjacent swift executable.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fixture="$root/Tests/HeadlessProcessFixture"
if [[ -z "${SWIFT:-}" ]]; then
  if [[ -n "${SWIFTC:-}" ]]; then
    SWIFT="$(dirname -- "$SWIFTC")/swift"
  else
    SWIFT=swift
  fi
fi
configuration=${CONFIGURATION:-release}
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$fixture/.build/ModuleCache}"

"$SWIFT" build --package-path "$root" --configuration "$configuration" --product ChromaHeadlessDemo
demo_bin_path=$("$SWIFT" build --package-path "$root" --configuration "$configuration" --show-bin-path)
"$SWIFT" build --package-path "$fixture" --configuration "$configuration" --product HeadlessProcessFixture
bin_path=$("$SWIFT" build --package-path "$fixture" --configuration "$configuration" --show-bin-path)
CHROMA_HEADLESS_DEMO="$demo_bin_path/ChromaHeadlessDemo" \
CHROMA_HEADLESS_FIXTURE="$bin_path/HeadlessProcessFixture" \
  "$SWIFT" test --package-path "$fixture" --configuration "$configuration"
