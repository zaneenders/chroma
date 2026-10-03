// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "HeadlessModeTests",
  platforms: [.macOS(.v27)],
  dependencies: [
    .package(name: "Chroma", path: ".."),
    // Keep the process driver out of Chroma's production dependency graph.
    .package(url: "https://github.com/swiftlang/swift-subprocess.git", exact: "1.0.0"),
  ],
  targets: [
    .executableTarget(
      name: "ChromaHeadlessDemo",
      dependencies: [
        .product(name: "Chroma", package: "Chroma"),
        .product(name: "ChromaHeadless", package: "Chroma"),
      ]
    ),
    .executableTarget(
      name: "HeadlessProcessFixture",
      dependencies: [
        .product(name: "Chroma", package: "Chroma"),
        .product(name: "ChromaHeadless", package: "Chroma"),
      ]
    ),
    .testTarget(
      name: "HeadlessProcessTests",
      dependencies: [
        "HeadlessProcessFixture",
        "ChromaHeadlessDemo",
        .product(name: "ChromaFont", package: "Chroma"),
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "ChromaHeadless", package: "Chroma"),
      ]
    ),
  ]
)
