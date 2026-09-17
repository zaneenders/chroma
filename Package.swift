// swift-tools-version: 6.4
import PackageDescription

var products: [Product] = [
  .executable(name: "chroma-install", targets: ["ChromaInstaller"]),
  .library(name: "Chroma", targets: ["Chroma"]),
  .library(name: "ChromaFont", targets: ["ChromaFont"]),
  .library(name: "HeadlessBackend", targets: ["HeadlessBackend"]),
]

var targets: [Target] = [
  .executableTarget(
    name: "ChromaInstaller",
    dependencies: [.product(name: "Subprocess", package: "swift-subprocess")]
  ),
  .testTarget(name: "ChromaInstallerTests", dependencies: ["ChromaInstaller"]),
  .testTarget(
    name: "ChromaTests",
    dependencies: ["Chroma", "ChromaFont", "HeadlessBackend"]
  ),
  .target(name: "Chroma", swiftSettings: [.strictMemorySafety()]),
  .target(
    name: "ChromaFont", exclude: ["README.md"], resources: [.copy("Resources")],
    swiftSettings: [.strictMemorySafety()]),
  .target(name: "HeadlessBackend", dependencies: ["Chroma"]),
]
#if os(macOS)
products.append(.library(name: "MetalBackend", targets: ["MetalBackend"]))
targets.append(contentsOf: [
  .testTarget(name: "MetalBackendTests", dependencies: ["MetalBackend"]),
  .target(
    name: "MetalBackend",
    dependencies: ["Chroma", "ChromaFont"],
    exclude: ["Shaders"],
    swiftSettings: [.strictMemorySafety()],
    plugins: [.plugin(name: "ShaderSourcePlugin")]
  ),
])
#endif

#if os(Linux)
products.append(.library(name: "WaylandBackend", targets: ["WaylandBackend"]))
targets.append(contentsOf: [
  .testTarget(
    name: "WaylandBackendTests",
    dependencies: ["WaylandBackend"],
    swiftSettings: [.strictMemorySafety()]
  ),
  .target(
    name: "WaylandBackend",
    dependencies: [
      "Chroma",
      "ChromaFont",
      "CWaylandClient",
      "CWaylandCursor",
      "CWaylandEGL",
      "CWaylandProtocols",
      "CEGL",
      "CGLES3",
      "CXKBKeyboard",
    ],
    exclude: ["Shaders"],
    swiftSettings: [.strictMemorySafety()],
    plugins: [.plugin(name: "ShaderSourcePlugin")]
  ),
  .systemLibrary(
    name: "CWaylandClient",
    path: "Sources/LinkedLibraries/CWaylandClient",
    pkgConfig: "wayland-client"
  ),
  .systemLibrary(
    name: "CWaylandCursor",
    path: "Sources/LinkedLibraries/CWaylandCursor",
    pkgConfig: "wayland-cursor"
  ),
  .systemLibrary(
    name: "CWaylandEGL",
    path: "Sources/LinkedLibraries/CWaylandEGL",
    pkgConfig: "wayland-egl"
  ),
  .systemLibrary(
    name: "CEGL",
    path: "Sources/LinkedLibraries/CEGL",
    pkgConfig: "egl"
  ),
  .systemLibrary(
    name: "CGLES3",
    path: "Sources/LinkedLibraries/CGLES3",
    pkgConfig: "glesv2"
  ),
  .target(
    name: "CWaylandProtocols",
    dependencies: ["CWaylandClient"],
    path: "Sources/LinkedLibraries/CWaylandProtocols",
    publicHeadersPath: "include"
  ),
  .target(
    name: "CXKBKeyboard",
    path: "Sources/LinkedLibraries/CXKBKeyboard",
    publicHeadersPath: "include",
    linkerSettings: [.linkedLibrary("xkbcommon")]
  ),
])
#endif

#if os(macOS) || os(Linux)
targets.append(contentsOf: [
  .executableTarget(name: "ShaderSourceGenerator"),
  .plugin(
    name: "ShaderSourcePlugin",
    capability: .buildTool(),
    dependencies: ["ShaderSourceGenerator"]
  ),
])
#endif

for target in targets where target.type != .plugin && target.type != .system {
  if ["CWaylandProtocols", "CXKBKeyboard"].contains(target.name) {
    target.cSettings = (target.cSettings ?? []) + [.treatAllWarnings(as: .error)]
  } else {
    target.swiftSettings = (target.swiftSettings ?? []) + [.treatAllWarnings(as: .error)]
  }
}

let package = Package(
  name: "chroma",
  platforms: [.macOS(.v27)],
  products: products,
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-subprocess.git", revision: "049ddf9")
  ],
  targets: targets
)
