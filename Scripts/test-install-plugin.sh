#!/bin/sh
set -eu
# Run the public command with a temporary HOME, never the user's real installation.
if [ "$(uname -s)" != Linux ]; then
  printf 'SKIP: Linux install plugin integration test\n'
  exit 0
fi
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
package="$tmp/app with spaces"
home="$tmp/test home"
mkdir -p "$package/Sources/InstallDemo/Resources" "$home"
ln -s "$root" "$tmp/chroma"
cat > "$package/Package.swift" <<'EOF'
// swift-tools-version: 6.4
import PackageDescription
let package = Package(
  name: "InstallFixture",
  products: [.executable(name: "InstallDemo", targets: ["InstallDemo"])],
  dependencies: [.package(path: "../chroma")],
  targets: [.executableTarget(
    name: "InstallDemo", dependencies: [.product(name: "ChromaFont", package: "chroma")],
    resources: [.copy("Resources")])])
EOF
cat > "$package/Sources/InstallDemo/main.swift" <<'EOF'
import ChromaFont
import Foundation
#if DEBUG
#error("The installer must always build release")
#endif
let atlas = HighResolutionFontAtlas()
let url = Bundle.module.url(forResource: "fixture", withExtension: "txt", subdirectory: "Resources")!
print("atlas=\(atlas.width) resource=\(try String(contentsOf: url, encoding: .utf8))")
EOF
printf 'installed-resource' > "$package/Sources/InstallDemo/Resources/fixture.txt"
install_fixture() {
  (cd "$package" && HOME="$home" swift package chroma-install "$@")
}
install_fixture --help > "$tmp/help"
grep -q -- '--without-profiling' "$tmp/help"
test ! -e "$home/.local"
install_fixture
binary="$home/.local/lib/local.InstallDemo/InstallDemo"
launcher="$home/.local/bin/InstallDemo"
test -L "$launcher"
test "$(readlink "$launcher")" = "$binary"
test "$("$launcher")" = 'atlas=2112 resource=installed-resource'
readelf -S "$binary" > "$tmp/sections"
grep -q '\.debug_info' "$tmp/sections"
grep -q '\.debug_line' "$tmp/sections"
readelf -d "$binary" > "$tmp/dynamic"
if grep -q 'Shared library: \[libswift' "$tmp/dynamic"; then
  echo 'Installed executable unexpectedly needs the shared Swift runtime' >&2
  exit 1
fi
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$home/.local/share/applications/local.InstallDemo.desktop"
fi
install_fixture --without-profiling
readelf -S "$binary" > "$tmp/sections"
if grep -q '\.debug_' "$tmp/sections"; then
  echo '--without-profiling left debug sections in the installed executable' >&2
  exit 1
fi
test "$("$launcher")" = 'atlas=2112 resource=installed-resource'
install_fixture
readelf -S "$binary" > "$tmp/sections"
grep -q '\.debug_info' "$tmp/sections"
cp "$binary" "$tmp/previous"
printf '\nthis is not valid Swift\n' >> "$package/Sources/InstallDemo/main.swift"
if install_fixture > "$tmp/failed-build.log" 2>&1; then
  echo 'Expected compilation failure' >&2
  exit 1
fi
cmp "$binary" "$tmp/previous"
mv "$package/.build" "$package/build-hidden"
test "$("$launcher")" = 'atlas=2112 resource=installed-resource'
mv "$package/build-hidden" "$package/.build"
for option in --prefix --config --configuration; do
  if install_fixture "$option" > "$tmp/invalid-option.log" 2>&1; then
    echo 'Expected invalid option failure' >&2
    exit 1
  fi
done
# Product selection must not silently choose one app when the package has several.
mkdir -p "$package/Sources/OtherDemo"
printf 'print("other")\n' > "$package/Sources/OtherDemo/main.swift"
cat > "$package/Package.swift" <<'EOF'
// swift-tools-version: 6.4
import PackageDescription
let package = Package(
  name: "InstallFixture",
  products: [
    .executable(name: "InstallDemo", targets: ["InstallDemo"]),
    .executable(name: "OtherDemo", targets: ["OtherDemo"]),
  ],
  dependencies: [.package(path: "../chroma")],
  targets: [
    .executableTarget(name: "InstallDemo", dependencies: [.product(name: "ChromaFont", package: "chroma")], resources: [.copy("Resources")]),
    .executableTarget(name: "OtherDemo"),
  ])
EOF
if install_fixture > "$tmp/ambiguous.log" 2>&1; then
  echo 'Expected ambiguous-product failure' >&2
  exit 1
fi
if ! grep -q 'Expected one executable product' "$tmp/ambiguous.log"; then
  cat "$tmp/ambiguous.log" >&2
  exit 1
fi
cmp "$binary" "$tmp/previous"
printf 'PASS: zero-config release install, default engine, profiling toggle, resources, safety, and product selection\n'
