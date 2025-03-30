// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "scribe",
  platforms: [
    .macOS("15.0")
  ],
  products: [
    .executable(name: "scribe", targets: ["Demo"]),
    .library(
      name: "Scribe",
      targets: ["Scribe"]),
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
    // Marcos
    .package(
      url: "https://github.com/swiftlang/swift-syntax.git",
      from: "600.0.1"),
  ],
  targets: [
    // MARK: Executable Targets
    .executableTarget(
      name: "Demo",
      dependencies: [
        "Scribe"
      ],
      swiftSettings: swiftSettings),
    // MARK: Targets
    .target(
      name: "Scribe",
      dependencies: [
        "TrackingMacros",
        .product(name: "Crypto", package: "swift-crypto"),
        .product(name: "SystemPackage", package: "swift-system"),
        .product(name: "Logging", package: "swift-log"),
      ],
      swiftSettings: swiftSettings),
    // MARK: Test Targets
    .testTarget(
      name: "ScribeTests",
      dependencies: [
        "Demo",
        "Scribe",
      ],
      swiftSettings: swiftSettings),
    // MARK: Macros
    .macro(
      name: "TrackingMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ],
      swiftSettings: swiftSettings
    ),
  ]
)

// MARK: SwiftSettings
let swiftSettings: [SwiftSetting] = [
  // Enable Swift 7.0 features for good habits now.
  .enableUpcomingFeature("ExistentialAny")
]
