// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "HeadlessProcessFixture",
  platforms: [.macOS(.v27)],
  dependencies: [.package(name: "Chroma", path: "../..")],
  targets: [
    .executableTarget(
      name: "HeadlessProcessFixture",
      dependencies: [
        .product(name: "Chroma", package: "Chroma"),
        .product(name: "ChromaHeadless", package: "Chroma"),
      ]
    )
  ]
)
