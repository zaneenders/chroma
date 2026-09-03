// swift-tools-version: 6.3
import PackageDescription

var products: [Product] = [
  .library(name: "Chroma", targets: ["Chroma"]),
  .library(name: "ChromaFont", targets: ["ChromaFont"]),
  .library(name: "HeadlessBackend", targets: ["HeadlessBackend"]),
]

var targets: [Target] = [
  .testTarget(
    name: "ChromaTests",
    dependencies: ["Chroma", "ChromaFont", "HeadlessBackend"]
  ),
  .target(name: "Chroma"),
  .target(name: "ChromaFont"),
  .target(name: "HeadlessBackend", dependencies: ["Chroma"]),
]
var backendTraits: Set<Trait> = []
var defaultBackendTraits: Set<String> = []

// Native backends and their build tooling are host-specific. SwiftPM traits can
// condition dependency edges and settings, but cannot condition products or
// target declarations; declaring both backends would make `swift build` probe
// Wayland system libraries on macOS and Metal build tooling on Linux.
#if os(macOS)
backendTraits.insert(
  .trait(
    name: "MetalBackend",
    description: "Build the native Metal backend on macOS."
  )
)
defaultBackendTraits.insert("MetalBackend")
products.append(.library(name: "MetalBackend", targets: ["MetalBackend"]))
targets.append(contentsOf: [
  .target(
    name: "MetalBackend",
    dependencies: ["Chroma", "ChromaFont"],
    exclude: ["Shaders"],
    // The product is only declared on macOS. Its API remains available whether
    // or not the demo-selection trait is enabled.
    swiftSettings: [.define("METAL_BACKEND")],
    plugins: [.plugin(name: "MetalSourcePlugin")]
  ),
  .executableTarget(name: "MetalSourceGenerator"),
  .plugin(
    name: "MetalSourcePlugin",
    capability: .buildTool(),
    dependencies: ["MetalSourceGenerator"]
  ),
])
#endif

#if os(Linux)
backendTraits.insert(
  .trait(
    name: "WaylandBackend",
    description: "Build the native Wayland/EGL/OpenGL ES backend on Linux."
  )
)
defaultBackendTraits.insert("WaylandBackend")
products.append(.library(name: "WaylandBackend", targets: ["WaylandBackend"]))
targets.append(contentsOf: [
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
    // The product is only declared on Linux. Its API remains available whether
    // or not the demo-selection trait is enabled.
    swiftSettings: [.define("WAYLAND_BACKEND")],
    plugins: [.plugin(name: "WaylandSourcePlugin")]
  ),
  .executableTarget(name: "WaylandSourceGenerator"),
  .plugin(
    name: "WaylandSourcePlugin",
    capability: .buildTool(),
    dependencies: ["WaylandSourceGenerator"]
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

let package = Package(
  name: "chroma",
  platforms: [.macOS(.v26)],
  products: products,
  traits: backendTraits.union([
    .default(enabledTraits: defaultBackendTraits)
  ]),
  targets: targets
)
