#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
collections=${1:?usage: storage.sh SWIFT_COLLECTIONS_CHECKOUT}
collections=$(cd "$collections" && pwd)
workspace=$(mktemp -d)
trap 'rm -rf "$workspace"' EXIT
mkdir -p "$workspace/Sources/Storage"
cp Benchmarks/StorageComparison/main.swift "$workspace/Sources/Storage/main.swift"
cat > "$workspace/Package.swift" <<EOF
// swift-tools-version: 6.4
import PackageDescription
let package = Package(name: "Storage", dependencies: [.package(path: "$collections")], targets: [.executableTarget(name: "Storage", dependencies: [.product(name: "BasicContainers", package: "swift-collections")])])
EOF
printf 'collections revision: '
git -C "$collections" rev-parse HEAD
git -C "$collections" status --short
swift run --package-path "$workspace" -c release
