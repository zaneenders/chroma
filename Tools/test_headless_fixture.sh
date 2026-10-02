#!/usr/bin/env bash
# Build a standalone consumer package, then exercise its real stdin/stdout pipes.
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

"$SWIFT" build --package-path "$fixture" --configuration "$configuration" --product HeadlessProcessFixture
bin_path=$("$SWIFT" build --package-path "$fixture" --configuration "$configuration" --show-bin-path)
PYTHONDONTWRITEBYTECODE=1 "${PYTHON:-python3}" "$root/Tools/test_headless_fixture.py" "$bin_path/HeadlessProcessFixture" -v
