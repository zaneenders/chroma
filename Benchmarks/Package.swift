// swift-tools-version: 6.4
import PackageDescription

var runnerDependencies: [Target.Dependency] = [
  "RenderFixtures",
  .product(name: "Chroma", package: "chroma"),
]
#if os(macOS)
runnerDependencies.append(.product(name: "MetalBackend", package: "chroma"))
#endif

let package = Package(
  name: "ChromaBenchmarks",
  platforms: [.macOS(.v27)],
  dependencies: [
    .package(path: ".."),
    .package(path: "../Examples"),
  ],
  targets: [
    .executableTarget(
      name: "InteractionBenchmark",
      dependencies: [
        .product(name: "InteractionFixtures", package: "Examples"),
        .product(name: "Chroma", package: "chroma"),
        .product(name: "ChromaTesting", package: "chroma"),
      ]),
    .executableTarget(
      name: "InputFrameBenchmark",
      dependencies: [
        .product(name: "Chroma", package: "chroma"),
        .product(name: "ChromaTesting", package: "chroma"),
      ]),
    .executableTarget(name: "CompareBenchmarks"),
    .testTarget(name: "CompareBenchmarksTests", dependencies: ["CompareBenchmarks"]),
    .target(name: "RenderFixtures", dependencies: [.product(name: "Chroma", package: "chroma")]),
    .executableTarget(name: "RenderBenchmark", dependencies: runnerDependencies),
    .testTarget(
      name: "RenderFixturesTests",
      dependencies: [
        "RenderFixtures", .product(name: "Chroma", package: "chroma"),
      ]),
  ]
)
