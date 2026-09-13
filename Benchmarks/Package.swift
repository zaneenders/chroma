// swift-tools-version: 6.4
import PackageDescription

var runnerDependencies: [Target.Dependency] = [
  "RenderFixtures",
  .product(name: "Chroma", package: "chroma"),
  .product(name: "RemoteProtocol", package: "chroma"),
  .product(name: "ProfileRecorderServer", package: "swift-profile-recorder"),
  .product(name: "Logging", package: "swift-log"),
]
#if os(macOS)
runnerDependencies.append(.product(name: "MetalBackend", package: "chroma"))
#endif

let package = Package(
  name: "ChromaBenchmarks",
  platforms: [.macOS(.v27)],
  dependencies: [
    .package(path: ".."),
    .package(url: "https://github.com/apple/swift-profile-recorder.git", .upToNextMinor(from: "0.3.13")),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.1"),
  ],
  targets: [
    .executableTarget(name: "CompareBenchmarks"),
    .testTarget(name: "CompareBenchmarksTests", dependencies: ["CompareBenchmarks"]),
    .target(name: "RenderFixtures", dependencies: [.product(name: "Chroma", package: "chroma")]),
    .executableTarget(
      name: "RenderBenchmark", dependencies: runnerDependencies,
      swiftSettings: [.unsafeFlags(["-Xcc", "-fno-omit-frame-pointer"])]),
    .testTarget(
      name: "RenderFixturesTests",
      dependencies: [
        "RenderFixtures", .product(name: "RemoteProtocol", package: "chroma"),
      ]),
  ]
)
