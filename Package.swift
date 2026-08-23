// swift-tools-version: 6.3
import PackageDescription

var products: [Product] = [
  .library(name: "Chroma", targets: ["Chroma"]),
  .library(name: "ChromaFont", targets: ["ChromaFont"]),
  .library(name: "HeadlessBackend", targets: ["HeadlessBackend"]),
  .library(name: "MetalBackend", targets: ["MetalBackend"]),
  .executable(name: "ChromaDemo", targets: ["ChromaDemo"]),
]

var demoDependencies: [Target.Dependency] = [
  "Chroma",
  .target(
    name: "MetalBackend",
    condition: .when(platforms: [.macOS], traits: ["MetalBackend"])
  ),
]

var demoSwiftSettings: [SwiftSetting] = [
  .define("METAL_BACKEND", .when(platforms: [.macOS], traits: ["MetalBackend"]))
]

// Wayland only exists on Linux; don't declare these targets at all on other
// platforms so they are never compiled (or probed via pkg-config) there.
#if os(Linux)
products.append(
  .library(name: "WaylandBackend", targets: ["WaylandBackend"])
)
demoDependencies.append(
  .target(
    name: "WaylandBackend",
    condition: .when(platforms: [.linux], traits: ["WaylandBackend"])
  )
)
demoSwiftSettings.append(
  .define("WAYLAND_BACKEND", .when(traits: ["WaylandBackend"]))
)
#endif

var targets: [Target] = [
  .executableTarget(
    name: "ChromaDemo",
    dependencies: demoDependencies,
    swiftSettings: demoSwiftSettings
  ),
  .testTarget(
    name: "ChromaTests",
    dependencies: ["Chroma", "ChromaFont", "HeadlessBackend"]
  ),
  .target(name: "Chroma"),
  .target(name: "ChromaFont"),
  .target(name: "HeadlessBackend", dependencies: ["Chroma"]),
  .target(
    name: "MetalBackend",
    dependencies: ["Chroma", "ChromaFont"],
    exclude: ["Shaders"],
    swiftSettings: [
      .define("METAL_TRAIT", .when(traits: ["MetalBackend"])),
      .define("METAL_BACKEND", .when(platforms: [.macOS], traits: ["MetalBackend"])),
    ],
    plugins: [
      .plugin(name: "MetalSourcePlugin")
    ]
  ),
  .executableTarget(name: "MetalSourceGenerator"),
  .plugin(
    name: "MetalSourcePlugin",
    capability: .buildTool(),
    dependencies: ["MetalSourceGenerator"]
  ),
]

#if os(Linux)
targets.append(contentsOf: [
  .target(
    name: "WaylandBackend",
    dependencies: [
      "Chroma",
      "ChromaFont",
      "CFreeType",
      "CFontconfig",
      "CWaylandClient",
      "CWaylandCursor",
      "CWaylandEGL",
      "CWaylandProtocols",
      "CEGL",
      "CGLES3",
    ],
    swiftSettings: [
      .define("WAYLAND_BACKEND", .when(traits: ["WaylandBackend"]))
    ]
  ),
  .systemLibrary(
    name: "CFreeType",
    path: "Sources/LinkedLibraries/CFreeType",
    pkgConfig: "freetype2"
  ),
  .systemLibrary(
    name: "CFontconfig",
    path: "Sources/LinkedLibraries/CFontconfig",
    pkgConfig: "fontconfig"
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
    path: "Sources/LinkedLibraries/CWaylandProtocols",
    publicHeadersPath: "include"
  ),
])
#endif

let package = Package(
  name: "chroma",
  platforms: [.macOS(.v14)],
  products: products,
  traits: [
    .trait(
      name: "MetalBackend",
      description: "Apple Metal rendering backend (macOS only, enabled by default)."
    ),
    .trait(
      name: "WaylandBackend",
      description: "Wayland/EGL/OpenGL ES rendering backend (Linux only). Build with `--traits WaylandBackend`."
    ),
    .default(enabledTraits: ["MetalBackend"]),
  ],
  targets: targets
)
