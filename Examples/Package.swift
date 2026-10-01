// swift-tools-version: 6.4
import PackageDescription

var dependencies: [Target.Dependency] = [
  "DemoContent",
  .product(name: "Chroma", package: "chroma"),
]
var targets: [Target] = [
  .testTarget(
    name: "DemoContentTests",
    dependencies: [
      "DemoContent", .product(name: "ChromaTesting", package: "chroma"),
    ]
  ),
  .target(
    name: "DemoContent",
    dependencies: [
      "DemoImages", .product(name: "Chroma", package: "chroma"),
    ]
  ),
  .target(
    name: "DemoImages",
    dependencies: [.product(name: "Chroma", package: "chroma")]
  ),
]

#if os(macOS)
dependencies.append(.product(name: "MetalBackend", package: "chroma"))
#elseif os(Linux)
dependencies.append(.product(name: "WaylandBackend", package: "chroma"))
#endif

let demos = ["PlayDemo", "ChatDemo", "ImageDemo"]
for demo in demos {
  targets.append(.executableTarget(name: demo, dependencies: dependencies))
}

let package = Package(
  name: "ChromaExamples",
  platforms: [.macOS(.v27)],
  products: demos.map { .executable(name: $0, targets: [$0]) },
  dependencies: [
    .package(path: "..")
  ],
  targets: targets
)
