// swift-tools-version: 6.4
import PackageDescription

var products: [Product] = [
  .library(name: "Chroma", targets: ["Chroma"]),
  .library(name: "ChromaFont", targets: ["ChromaFont"]),
  .library(name: "HeadlessBackend", targets: ["HeadlessBackend"]),
  .library(name: "RemoteProtocol", targets: ["RemoteProtocol"]),
  .library(name: "RemoteServer", targets: ["RemoteServer"]),
]

var targets: [Target] = [
  .testTarget(
    name: "RemoteServerTests",
    dependencies: [
      "RemoteServer", "RemoteProtocol", "Chroma",
      .product(name: "NIOPosix", package: "swift-nio"),
      .product(name: "NIOEmbedded", package: "swift-nio"),
    ]),
  .testTarget(
    name: "ChromaTests",
    dependencies: ["Chroma", "ChromaFont", "HeadlessBackend"]
  ),
  .testTarget(
    name: "RemoteProtocolTests",
    dependencies: [
      "Chroma", "RemoteProtocol",
      .product(name: "NIOEmbedded", package: "swift-nio"),
      .product(name: "NIOCore", package: "swift-nio"),
    ]
  ),
  .target(name: "Chroma", swiftSettings: [.strictMemorySafety()]),
  .target(
    name: "ChromaFont", exclude: ["README.md"], resources: [.copy("Resources")],
    swiftSettings: [.strictMemorySafety()]),
  .target(name: "HeadlessBackend", dependencies: ["Chroma"]),
  .target(
    name: "RemoteProtocol",
    dependencies: ["Chroma", .product(name: "NIOCore", package: "swift-nio")],
    swiftSettings: [.strictMemorySafety()]
  ),
  .target(
    name: "RemoteServer",
    dependencies: [
      "Chroma", "RemoteProtocol",
      .product(name: "Logging", package: "swift-log"),
      .product(name: "NIOCore", package: "swift-nio"),
      .product(name: "NIOPosix", package: "swift-nio"),
    ],
    swiftSettings: [.strictMemorySafety()]
  ),
]
var backendTraits: Set<Trait> = []
var defaultBackendTraits: Set<String> = []

#if os(macOS)
backendTraits.insert(
  .trait(
    name: "MetalBackend",
    description: "Build the native Metal backend on macOS."
  )
)
defaultBackendTraits.insert("MetalBackend")
products.append(.library(name: "MetalBackend", targets: ["MetalBackend"]))
products.append(.library(name: "RemoteMetalClient", targets: ["RemoteMetalClient"]))
targets.append(contentsOf: [
  .testTarget(name: "MetalBackendTests", dependencies: ["MetalBackend"]),
  .testTarget(name: "RemoteMetalClientTests", dependencies: ["RemoteMetalClient", "Chroma", "RemoteProtocol"]),
  .target(
    name: "MetalBackend",
    dependencies: ["Chroma", "ChromaFont"],
    exclude: ["Shaders"],
    swiftSettings: [.define("METAL_BACKEND"), .strictMemorySafety()],
    plugins: [.plugin(name: "MetalSourcePlugin")]
  ),
  .target(
    name: "RemoteMetalClient",
    dependencies: [
      "Chroma", "MetalBackend", "RemoteProtocol",
      .product(name: "NIOCore", package: "swift-nio"),
      .product(name: "NIOPosix", package: "swift-nio"),
    ],
    swiftSettings: [.define("METAL_BACKEND"), .strictMemorySafety()]
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
    swiftSettings: [.define("WAYLAND_BACKEND"), .strictMemorySafety()],
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
  platforms: [.macOS(.v27)],
  products: products,
  traits: backendTraits.union([
    .default(enabledTraits: defaultBackendTraits)
  ]),
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.0"),
  ],
  targets: targets
)
