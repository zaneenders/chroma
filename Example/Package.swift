// swift-tools-version: 6.3
import PackageDescription

var dependencies: [Target.Dependency] = [
  .product(name: "Chroma", package: "chroma")
]
var swiftSettings: [SwiftSetting] = []
var chromaTraits: Set<Package.Dependency.Trait> = []

#if os(macOS)
chromaTraits.insert("MetalBackend")
dependencies.append(.product(name: "MetalBackend", package: "chroma"))
swiftSettings.append(.define("METAL_BACKEND"))
#elseif os(Linux)
chromaTraits.insert("WaylandBackend")
dependencies.append(.product(name: "WaylandBackend", package: "chroma"))
swiftSettings.append(.define("WAYLAND_BACKEND"))
#endif

let package = Package(
  name: "ChromaExample",
  platforms: [.macOS(.v26)],
  dependencies: [
    .package(path: "..", traits: chromaTraits)
  ],
  targets: [
    .executableTarget(
      name: "ChromaDemo",
      dependencies: dependencies,
      swiftSettings: swiftSettings
    )
  ]
)
