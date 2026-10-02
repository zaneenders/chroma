// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "HeadlessProcessFixture",
  platforms: [.macOS(.v27)],
  dependencies: [
    .package(name: "Chroma", path: "../.."),
    // Keep the process driver out of Chroma's production dependency graph.
    .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "1.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "HeadlessProcessFixture",
      dependencies: [
        .product(name: "Chroma", package: "Chroma"),
        .product(name: "ChromaHeadless", package: "Chroma"),
      ]
    ),
    .testTarget(
      name: "HeadlessProcessTests",
      dependencies: [.product(name: "Subprocess", package: "swift-subprocess")]
    ),
  ]
)
