// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "chroma",
  platforms: [
    .macOS("15.0")
  ],
  products: [
    .executable(name: "chroma", targets: ["Demo"]),
    .library(
      name: "Chroma",
      targets: ["Chroma"]),
  ],
  dependencies: [
    /*
    TODO remove DocC as it is only used for generating documentation and
    could be one with a script.
    */
    .package(
      url: "https://github.com/apple/swift-docc-plugin.git",
      from: "1.3.0"),
    // Used for better file system abstractions.
    .package(url: "https://github.com/apple/swift-system.git", from: "1.4.2"),
    // Logging because we are taking over the terminal display.
    .package(
      url: "https://github.com/apple/swift-log.git",
      from: "1.6.2"),
    // Sha256 for a sort of Merkle tree hashing.
    .package(
      url: "https://github.com/apple/swift-crypto.git",
      from: "3.12.2"),
  ],
  targets: [
    // MARK: Executable Targets
    .executableTarget(
      name: "Demo",
      dependencies: [
        "Chroma"
      ],
      swiftSettings: swiftSettings),
    // MARK: Targets
    .target(
      name: "Chroma",
      dependencies: [
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "SystemPackage", package: "swift-system"),
        .product(name: "Logging", package: "swift-log"),
      ],
      swiftSettings: swiftSettings),
    // MARK: Test Targets
    .testTarget(
      name: "ChromaTests",
      dependencies: [
        "Demo",
        "Chroma",
      ],
      swiftSettings: swiftSettings),
  ]
)

// MARK: SwiftSettings
let swiftSettings: [SwiftSetting] = [
  // Enable Swift 7.0 features for good habits now.
  .enableUpcomingFeature("ExistentialAny")
]
