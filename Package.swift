// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "HelloTriangle",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "ImmediateGUI", targets: ["ImmediateGUI"]),
    .library(name: "MetalBackend", targets: ["MetalBackend"]),
    .library(name: "WaylandBackend", targets: ["WaylandBackend"]),
  ],
  traits: [
    .trait(
      name: "MetalBackend",
      description: "Apple Metal rendering backend (macOS only, enabled by default)."
    ),
    .trait(
      name: "WaylandBackend",
      description: "Wayland rendering backend (stub, not yet implemented). Build with `--traits WaylandBackend`."
    ),
    .default(enabledTraits: ["MetalBackend"]),
  ],
  targets: [
    .executableTarget(
      name: "HelloTriangle",
      dependencies: [
        "ImmediateGUI",
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
        .define("WAYLAND_BACKEND", .when(traits: ["WaylandBackend"])),
      ]
    ),
    .target(name: "ImmediateGUI"),
    .target(
      name: "MetalBackend",
      dependencies: ["ImmediateGUI"],
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
      dependencies: ["ImmediateGUI"],
      swiftSettings: [
        .define("WAYLAND_BACKEND", .when(traits: ["WaylandBackend"]))
      ]
    ),
    .executableTarget(name: "MetalSourceGenerator"),
    .plugin(
      name: "MetalSourcePlugin",
      capability: .buildTool(),
      dependencies: ["MetalSourceGenerator"]
    ),
  ]
)
