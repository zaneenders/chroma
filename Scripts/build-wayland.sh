#!/usr/bin/env bash
# Ubuntu 24.04's Wayland headers predate wl_pointer_listener.warp.
# Install this pinned upstream release into an isolated, caller-owned prefix.
set -euo pipefail
prefix=${1:?usage: build-wayland.sh ABSOLUTE_PREFIX}
case "$prefix" in /*) ;; *) echo 'Prefix must be absolute.' >&2; exit 2;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
curl --fail --location --retry 3 \
  https://gitlab.freedesktop.org/wayland/wayland/-/releases/1.26.0/downloads/wayland-1.26.0.tar.xz \
  -o wayland.tar.xz
# SHA256 published in the upstream 1.26.0 release announcement.
echo '64176eaa46e4969903e286f8e5ef8331affc17fdf03ac9b58381d2b23162b7a3  wayland.tar.xz' | sha256sum --check
tar -xf wayland.tar.xz
meson setup build wayland-1.26.0 --prefix "$prefix" --libdir lib \
  -Ddocumentation=false -Dtests=false -Ddtd_validation=false
meson compile -C build
meson install -C build
