// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "SwiftFrameArenaPrototype",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "FrameArena", targets: ["FrameArena"]),
        .executable(name: "arena-benchmarks", targets: ["ArenaBenchmarks"]),
    ],
    targets: [
        .target(name: "FrameArena", swiftSettings: [.enableExperimentalFeature("Lifetimes")]),
        .executableTarget(name: "ArenaBenchmarks", dependencies: ["FrameArena"],
                          swiftSettings: [.enableExperimentalFeature("Lifetimes")]),
        .testTarget(name: "FrameArenaTests", dependencies: ["FrameArena"],
                    swiftSettings: [.enableExperimentalFeature("Lifetimes")]),
    ]
)
