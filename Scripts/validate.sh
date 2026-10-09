#!/usr/bin/env bash
# Explicitly invoked local checks. No resolution updates or stderr filtering.
set -euo pipefail
cd "$(dirname "$0")/.."

stage=${1:-all}
if [ "$#" -gt 0 ]; then shift; fi
jobs=${CHROMA_BUILD_JOBS:-2}
case "$jobs" in ''|*[!0-9]*|0) echo 'CHROMA_BUILD_JOBS must be a positive integer' >&2; exit 2;; esac

preflight() {
  swift --version
  if ! swift --version | grep -Eq 'Swift version 6\.4([ .-]|$)'; then
    echo 'Validation requires the Swift 6.4 toolchain (.swift-version).' >&2
    return 1
  fi
  case "$(uname -s)" in
    Linux)
      pkg-config --atleast-version=1.26 wayland-client || {
        echo 'Wayland 1.26+ headers and libraries are required (wl_pointer_listener.warp).' >&2
        return 1
      }
      pkg-config --modversion wayland-client wayland-cursor wayland-egl egl glesv2 xkbcommon
      ;;
    Darwin)
      if [ "$(sw_vers -productVersion | cut -d. -f1)" -lt 27 ]; then
        echo 'Tests require macOS 27 or newer (Package.swift deployment target).' >&2
        return 1
      fi
      xcodebuild -version
      ;;
    *) echo 'Validation supports Linux and macOS.' >&2; return 1;;
  esac
}

run_stage() {
  local check=$1
  shift
  case "$check" in
    preflight) preflight;;
    format)
      swift format lint --strict --recursive Sources Tests Benchmarks/Sources Benchmarks/Tests \
        HeadlessModeTests/Sources HeadlessModeTests/Tests Plugins
      ;;
    root-tests) swift test --force-resolved-versions --jobs "$jobs" "$@";;
    benchmark-tests) swift test --package-path Benchmarks --force-resolved-versions --jobs "$jobs" "$@";;
    headless-tests) swift test --package-path HeadlessModeTests --force-resolved-versions --jobs "$jobs" "$@";;
    root-release) swift build -c release --force-resolved-versions --jobs "$jobs" "$@";;
    benchmark-release) swift build --package-path Benchmarks -c release --force-resolved-versions --jobs "$jobs" "$@";;
    headless-release) swift build --package-path HeadlessModeTests -c release --force-resolved-versions --jobs "$jobs" "$@";;
    lockfiles) git diff --exit-code -- Package.resolved Benchmarks/Package.resolved HeadlessModeTests/Package.resolved;;
    *) echo "Unknown validation stage: $check" >&2; return 2;;
  esac
}

if [ "$stage" = all ]; then
  for check in preflight format root-tests benchmark-tests headless-tests root-release benchmark-release headless-release lockfiles; do
    echo "==> $check"
    run_stage "$check" "$@"
  done
else
  run_stage "$stage" "$@"
fi
