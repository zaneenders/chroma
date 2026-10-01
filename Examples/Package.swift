// swift-tools-version: 6.4
import PackageDescription

var dependencies: [Target.Dependency] = [
  "DemoContent",
  .product(name: "Chroma", package: "chroma"),
]
var targets: [Target] = [
  .target(name: "InteractionFixtures", dependencies: [.product(name: "Chroma", package: "chroma")]),
  .testTarget(
    name: "InteractionFixturesTests",
    dependencies: ["InteractionFixtures", .product(name: "ChromaTesting", package: "chroma")]),
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

let demos = ["PlayDemo", "ChatDemo", "ImageDemo", "InteractionDemo"]
for demo in demos {
  var demoDependencies = dependencies
  if demo == "InteractionDemo" {
    demoDependencies[0] = "InteractionFixtures"
  }
  targets.append(.executableTarget(name: demo, dependencies: demoDependencies))
}

let package = Package(
  name: "ChromaExamples",
  platforms: [.macOS(.v27)],
  products: demos.map { .executable(name: $0, targets: [$0]) } + [
    .library(name: "InteractionFixtures", targets: ["InteractionFixtures"])
  ],
  dependencies: [
    .package(path: "..")
  ],
  targets: targets
)
