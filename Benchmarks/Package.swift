// swift-tools-version: 6.4
import PackageDescription

var runnerDependencies: [Target.Dependency] = [
  "RenderFixtures",
  .product(name: "Chroma", package: "chroma"),
]
#if os(macOS)
runnerDependencies.append(.product(name: "MetalBackend", package: "chroma"))
#elseif os(Linux)
runnerDependencies.append(.product(name: "WaylandBackend", package: "chroma"))
#endif

let package = Package(
  name: "ChromaBenchmarks",
  platforms: [.macOS(.v27)],
  products: [.library(name: "StressFixtures", targets: ["StressFixtures"])],
  dependencies: [
    .package(name: "chroma", path: "..")
  ],
  targets: [
    .target(name: "StressFixtures", dependencies: [.product(name: "Chroma", package: "chroma")]),
    .executableTarget(
      name: "StressExample",
      dependencies: [
        "StressFixtures", .product(name: "ChromaApp", package: "chroma"),
        .product(name: "ChromaMarkdown", package: "chroma"),
      ]),
    .executableTarget(
      name: "StressBenchmark",
      dependencies: [
        "StressFixtures", .product(name: "ChromaTesting", package: "chroma"),
      ]),
    .testTarget(
      name: "StressFixturesTests",
      dependencies: [
        "StressFixtures", .product(name: "ChromaTesting", package: "chroma"),
      ]),
    .executableTarget(
      name: "LayoutBenchmark",
      dependencies: [
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
