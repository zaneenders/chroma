// swift-tools-version: 6.3
import PackageDescription

let package = Package(
  name: "chroma",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "Chroma", targets: ["Chroma"]),
    .library(name: "ChromaFont", targets: ["ChromaFont"]),
    .library(name: "HeadlessBackend", targets: ["HeadlessBackend"]),
    .library(name: "MetalBackend", targets: ["MetalBackend"]),
    .executable(name: "ChromaDemo", targets: ["ChromaDemo"]),
    .library(name: "WaylandBackend", targets: ["WaylandBackend"]),
  ],
  traits: [
    .trait(
      name: "MetalBackend",
      description: "Apple Metal rendering backend (macOS only, enabled by default)."
    ),
    .trait(
      name: "WaylandBackend",
      description: "Wayland/EGL/OpenGL ES rendering backend. Build with `--traits WaylandBackend`."
    ),
    .default(enabledTraits: ["MetalBackend"]),
  ],
  targets: [
    .executableTarget(
      name: "ChromaDemo",
      dependencies: [
        "Chroma",
        .target(
          name: "MetalBackend",
          condition: .when(platforms: [.macOS], traits: ["MetalBackend"])
        ),
        .target(
          name: "WaylandBackend",
          condition: .when(platforms: [.linux], traits: ["WaylandBackend"])
        ),
      ],
      swiftSettings: [
        .define("METAL_BACKEND", .when(platforms: [.macOS], traits: ["MetalBackend"])),
        .define(
          "WAYLAND_BACKEND",
          .when(platforms: [.linux], traits: ["WaylandBackend"])
        ),
      ]
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
    .target(
      name: "WaylandBackend",
      dependencies: [
        "Chroma",
        "ChromaFont",
        "CWaylandClient",
        "CWaylandEGL",
        "CWaylandProtocols",
        "CEGL",
        "CGLES3",
      ]
      swiftSettings: [
        .define("WAYLAND_BACKEND", .when(traits: ["WaylandBackend"]))
      ]
    ),
    .systemLibrary(
      name: "CWaylandClient",
      path: "Sources/LinkedLibraries/CWaylandClient",
      pkgConfig: "wayland-client"
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
    .executableTarget(name: "MetalSourceGenerator"),
    .plugin(
      name: "MetalSourcePlugin",
      capability: .buildTool(),
      dependencies: ["MetalSourceGenerator"]
    ),
  ]
)
